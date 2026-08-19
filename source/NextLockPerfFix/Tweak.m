#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <objc/runtime.h>
#import <os/lock.h>
#include <string.h>
#if defined(__arm64e__) && __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif

extern void MSHookFunction(void *symbol, void *replace, void **result);
extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

// NextLock 1.1.4 LockGlyphTime.dylib UUIDs and helper offsets, verified from
// the exact live binary captured from the affected device.
//
// arm64 : C7EBC4D1-EAD4-3320-A27F-34E86C25F776  helper +0xAE18
// arm64e: 7BE1428A-C4B0-38F8-8120-7BACBF220731  helper +0xAF74
//
// Test 1 proved the transparency helper hook was active, but SpringBoard CPU
// still rose because LockGlyphTime can create fresh UIImage objects from the
// same NSData during repeated layout passes. That defeats an object-pointer
// cache even though the image content itself is unchanged.
//
// Test 2 keeps every NextLock feature and the exact original transparency
// decision, but also memoizes +[UIImage imageWithData:] ONLY when the direct
// caller is inside the verified LockGlyphTime 1.1.4 __TEXT range. Repeated
// layouts then reuse the same immutable UIImage, so the original expensive
// alpha scan runs once per distinct photo/sticker content instead of once per
// layout pass.

static const uint8_t kNextLock114Arm64UUID[16] = {
    0xC7, 0xEB, 0xC4, 0xD1, 0xEA, 0xD4, 0x33, 0x20,
    0xA2, 0x7F, 0x34, 0xE8, 0x6C, 0x25, 0xF7, 0x76
};

static const uint8_t kNextLock114Arm64eUUID[16] = {
    0x7B, 0xE1, 0x42, 0x8A, 0xC4, 0xB0, 0x38, 0xF8,
    0x81, 0x20, 0x7B, 0xAC, 0xBF, 0x22, 0x07, 0x31
};

static const uintptr_t kNextLock114Arm64TransparencyOffset   = 0xAE18;
static const uintptr_t kNextLock114Arm64eTransparencyOffset = 0xAF74;

static BOOL (*NLOriginalHasRealTransparency)(UIImage *image) = NULL;
static UIImage *(*NLOriginalImageWithData)(id, SEL, NSData *) = NULL;

static NSMapTable<UIImage *, NSNumber *> *NLTransparencyCache = nil;
static NSMapTable<NSData *, UIImage *> *NLDataPointerImageCache = nil;
static NSCache<NSString *, UIImage *> *NLDataFingerprintImageCache = nil;

static os_unfair_lock NLTransparencyLock = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock NLImageCacheLock = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock NLInstallLock = OS_UNFAIR_LOCK_INIT;

static BOOL NLTransparencyHookInstalled = NO;
static BOOL NLImageHookInstalled = NO;
static uintptr_t NLLockGlyphTextStart = 0;
static uintptr_t NLLockGlyphTextEnd = 0;

__attribute__((used)) static const char *NLPerfFixMarker =
    "NextLockPerfFix 1.1.5-test2 targeted-image-cache transparency-cache exact-semantics";

static void NLEnsureCaches(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NLTransparencyCache = [[NSMapTable alloc]
            initWithKeyOptions:(NSPointerFunctionsWeakMemory |
                                NSPointerFunctionsObjectPointerPersonality)
            valueOptions:NSPointerFunctionsStrongMemory
            capacity:8];

        // Fast path when LockGlyphTime reuses the same NSData object.
        NLDataPointerImageCache = [[NSMapTable alloc]
            initWithKeyOptions:(NSPointerFunctionsWeakMemory |
                                NSPointerFunctionsObjectPointerPersonality)
            valueOptions:NSPointerFunctionsStrongMemory
            capacity:8];

        // Fallback when LockGlyphTime reconstructs an equivalent NSData object.
        NLDataFingerprintImageCache = [[NSCache alloc] init];
        NLDataFingerprintImageCache.countLimit = 12;
    });
}

static BOOL NLCachedHasRealTransparency(UIImage *image) {
    if (image == nil || NLOriginalHasRealTransparency == NULL) {
        return NO;
    }

    NLEnsureCaches();

    os_unfair_lock_lock(&NLTransparencyLock);
    NSNumber *cached = [NLTransparencyCache objectForKey:image];
    os_unfair_lock_unlock(&NLTransparencyLock);

    if (cached != nil) {
        return cached.boolValue;
    }

    // Preserve the exact 1.1.4 decision on first encounter. The original helper
    // performs CGBitmapContextCreate + DrawImage + alpha-byte scanning.
    BOOL result = NLOriginalHasRealTransparency(image);

    os_unfair_lock_lock(&NLTransparencyLock);
    [NLTransparencyCache setObject:@(result) forKey:image];
    os_unfair_lock_unlock(&NLTransparencyLock);

    return result;
}

// Cheap, stable content fingerprint. It deliberately avoids hashing every byte
// on every layout. Length plus samples from the beginning/middle/end makes a
// collision between user-selected photos/stickers practically impossible while
// touching at most 288 bytes even for multi-megabyte images.
static uint64_t NLFingerprintBytes(NSData *data) {
    const NSUInteger len = data.length;
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    uint64_t h = 1469598103934665603ULL;

    #define NL_FNV_BYTE(v) do { h ^= (uint64_t)(v); h *= 1099511628211ULL; } while (0)

    for (unsigned shift = 0; shift < sizeof(NSUInteger) * 8; shift += 8) {
        NL_FNV_BYTE((len >> shift) & 0xff);
    }

    if (bytes != NULL && len > 0) {
        const NSUInteger window = MIN((NSUInteger)96, len);
        for (NSUInteger i = 0; i < window; i++) NL_FNV_BYTE(bytes[i]);

        if (len > window) {
            NSUInteger mid = len / 2;
            NSUInteger start = (mid > window / 2) ? mid - window / 2 : 0;
            if (start + window > len) start = len - window;
            for (NSUInteger i = 0; i < window; i++) NL_FNV_BYTE(bytes[start + i]);
        }

        if (len > window * 2) {
            NSUInteger start = len - window;
            for (NSUInteger i = 0; i < window; i++) NL_FNV_BYTE(bytes[start + i]);
        }
    }

    #undef NL_FNV_BYTE
    return h;
}

static NSString *NLDataKey(NSData *data) {
    uint64_t fp = NLFingerprintBytes(data);
    return [NSString stringWithFormat:@"%llu-%016llx",
            (unsigned long long)data.length,
            (unsigned long long)fp];
}

static UIImage *NLCachedImageWithData(id cls, SEL cmd, NSData *data) {
    // IMPORTANT: take the return address directly in this replacement. A helper
    // function would see NextLockPerfFix as its caller and would defeat the
    // module-range gate. objc_msgSend tail-calls the IMP, so LR still points to
    // the LockGlyphTime call site here.
    void *rawRA = __builtin_return_address(0);
#if defined(__arm64e__) && __has_include(<ptrauth.h>)
    rawRA = ptrauth_strip(rawRA, ptrauth_key_return_address);
#endif
    const uintptr_t ra = (uintptr_t)rawRA;
    const BOOL fromLockGlyphTime = NLLockGlyphTextStart != 0 &&
                                   ra >= NLLockGlyphTextStart &&
                                   ra < NLLockGlyphTextEnd;

    if (NLOriginalImageWithData == NULL || data == nil || !fromLockGlyphTime) {
        return NLOriginalImageWithData ? NLOriginalImageWithData(cls, cmd, data) : nil;
    }

    NLEnsureCaches();

    os_unfair_lock_lock(&NLImageCacheLock);
    UIImage *image = [NLDataPointerImageCache objectForKey:data];
    os_unfair_lock_unlock(&NLImageCacheLock);
    if (image != nil) {
        return image;
    }

    NSString *key = NLDataKey(data);

    os_unfair_lock_lock(&NLImageCacheLock);
    image = [NLDataFingerprintImageCache objectForKey:key];
    os_unfair_lock_unlock(&NLImageCacheLock);
    if (image != nil) {
        os_unfair_lock_lock(&NLImageCacheLock);
        [NLDataPointerImageCache setObject:image forKey:data];
        os_unfair_lock_unlock(&NLImageCacheLock);
        return image;
    }

    // First decode for this distinct content. Preserve UIImage's original API
    // semantics; only the resulting immutable object is retained for reuse.
    image = NLOriginalImageWithData(cls, cmd, data);
    if (image == nil) {
        return nil;
    }

    os_unfair_lock_lock(&NLImageCacheLock);
    [NLDataPointerImageCache setObject:image forKey:data];
    [NLDataFingerprintImageCache setObject:image forKey:key];
    os_unfair_lock_unlock(&NLImageCacheLock);

    return image;
}

static BOOL NLFindUUIDTextAndOffset(const struct mach_header *mh,
                                    uintptr_t *offsetOut,
                                    uintptr_t *textStartOut,
                                    uintptr_t *textEndOut,
                                    const char **archOut) {
    if (mh == NULL || offsetOut == NULL) return NO;

    const uint8_t *uuid = NULL;
    uint32_t ncmds = 0;
    const uint8_t *cursor = NULL;
    uint64_t textVMAddr = 0;
    uint64_t textVMSize = 0;

    if (mh->magic == MH_MAGIC_64) {
        const struct mach_header_64 *h64 = (const struct mach_header_64 *)mh;
        ncmds = h64->ncmds;
        cursor = (const uint8_t *)(h64 + 1);
    } else {
        return NO;
    }

    for (uint32_t i = 0; i < ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(struct load_command)) return NO;

        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            uuid = ((const struct uuid_command *)lc)->uuid;
        } else if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strncmp(seg->segname, "__TEXT", sizeof(seg->segname)) == 0) {
                textVMAddr = seg->vmaddr;
                textVMSize = seg->vmsize;
            }
        }
        cursor += lc->cmdsize;
    }

    if (uuid == NULL || textVMSize == 0) return NO;

    if (memcmp(uuid, kNextLock114Arm64UUID, sizeof(kNextLock114Arm64UUID)) == 0) {
        *offsetOut = kNextLock114Arm64TransparencyOffset;
        if (archOut) *archOut = "arm64";
    } else if (memcmp(uuid, kNextLock114Arm64eUUID, sizeof(kNextLock114Arm64eUUID)) == 0) {
        *offsetOut = kNextLock114Arm64eTransparencyOffset;
        if (archOut) *archOut = "arm64e";
    } else {
        return NO;
    }

    uintptr_t slide = (uintptr_t)mh - (uintptr_t)textVMAddr;
    if (textStartOut) *textStartOut = slide + (uintptr_t)textVMAddr;
    if (textEndOut) *textEndOut = slide + (uintptr_t)textVMAddr + (uintptr_t)textVMSize;
    return YES;
}

static void NLInstallHooks(const struct mach_header *mh,
                           uintptr_t helperOffset,
                           uintptr_t textStart,
                           uintptr_t textEnd,
                           const char *matchedArch) {
    os_unfair_lock_lock(&NLInstallLock);

    NLLockGlyphTextStart = textStart;
    NLLockGlyphTextEnd = textEnd;

    if (!NLTransparencyHookInstalled) {
        void *target = (void *)((uintptr_t)mh + helperOffset);
        MSHookFunction(target,
                       (void *)&NLCachedHasRealTransparency,
                       (void **)&NLOriginalHasRealTransparency);
        if (NLOriginalHasRealTransparency != NULL) {
            NLTransparencyHookInstalled = YES;
        }
    }

    if (!NLImageHookInstalled) {
        Class meta = object_getClass([UIImage class]);
        if (meta != Nil) {
            MSHookMessageEx(meta,
                            @selector(imageWithData:),
                            (IMP)&NLCachedImageWithData,
                            (IMP *)&NLOriginalImageWithData);
            if (NLOriginalImageWithData != NULL) {
                NLImageHookInstalled = YES;
            }
        }
    }

    if (NLTransparencyHookInstalled && NLImageHookInstalled) {
        NSLog(@"[NextLockPerfFix] Test2 installed (%s, +0x%lx, text=%p-%p)",
              matchedArch ?: "unknown",
              (unsigned long)helperOffset,
              (void *)textStart,
              (void *)textEnd);
    }

    os_unfair_lock_unlock(&NLInstallLock);
}

static void NLImageAdded(const struct mach_header *mh, intptr_t vmaddrSlide) {
    (void)vmaddrSlide;

    uintptr_t helperOffset = 0;
    uintptr_t textStart = 0;
    uintptr_t textEnd = 0;
    const char *matchedArch = NULL;
    if (!NLFindUUIDTextAndOffset(mh, &helperOffset, &textStart, &textEnd, &matchedArch)) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NLInstallHooks(mh, helperOffset, textStart, textEnd, matchedArch);
    });
}

__attribute__((constructor))
static void NLPerfFixInit(void) {
    @autoreleasepool {
        _dyld_register_func_for_add_image(NLImageAdded);
    }
}
