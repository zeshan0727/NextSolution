#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <os/lock.h>
#include <string.h>

extern void MSHookFunction(void *symbol, void *replace, void **result);

// NextLock 1.1.4 LockGlyphTime.dylib UUIDs and helper offsets, verified from
// the exact live binary captured from the affected device.
//
// arm64 : C7EBC4D1-EAD4-3320-A27F-34E86C25F776  helper +0xAE18
// arm64e: 7BE1428A-C4B0-38F8-8120-7BACBF220731  helper +0xAF74
//
// The helper performs the full-pixel transparency test used to preserve the
// distinction between transparent stickers (AspectFit / no crop) and normal
// photos (AspectFill / corner clipping). We do NOT change that algorithm.
// We only memoize its exact result for each immutable UIImage instance so
// repeated layoutSubviews passes do not redraw and rescan the same bitmap.

static const uint8_t kNextLock114Arm64UUID[16] = {
    0xC7, 0xEB, 0xC4, 0xD1, 0xEA, 0xD4, 0x33, 0x20,
    0xA2, 0x7F, 0x34, 0xE8, 0x6C, 0x25, 0xF7, 0x76
};

static const uint8_t kNextLock114Arm64eUUID[16] = {
    0x7B, 0xE1, 0x42, 0x8A, 0xC4, 0xB0, 0x38, 0xF8,
    0x81, 0x20, 0x7B, 0xAC, 0xBF, 0x22, 0x07, 0x31
};

static const uintptr_t kNextLock114Arm64TransparencyOffset  = 0xAE18;
static const uintptr_t kNextLock114Arm64eTransparencyOffset = 0xAF74;

static BOOL (*NLOriginalHasRealTransparency)(UIImage *image) = NULL;
static NSMapTable<UIImage *, NSNumber *> *NLTransparencyCache = nil;
static os_unfair_lock NLCacheLock = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock NLInstallLock = OS_UNFAIR_LOCK_INIT;
static BOOL NLHookInstalled = NO;

// Kept as a binary marker so the test package can be audited with `strings`.
__attribute__((used)) static const char *NLPerfFixMarker =
    "NextLockPerfFix 1.1.5-test transparency-cache exact-semantics";

static void NLEnsureCache(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Pointer personality is deliberate: UIImage is immutable for our use,
        // and a newly loaded preference image gets a new object and therefore a
        // new cache entry. Weak keys prevent retaining old custom photos.
        NLTransparencyCache = [[NSMapTable alloc]
            initWithKeyOptions:(NSPointerFunctionsWeakMemory |
                                NSPointerFunctionsObjectPointerPersonality)
            valueOptions:NSPointerFunctionsStrongMemory
            capacity:8];
    });
}

static BOOL NLCachedHasRealTransparency(UIImage *image) {
    if (image == nil || NLOriginalHasRealTransparency == NULL) {
        return NO;
    }

    NLEnsureCache();

    os_unfair_lock_lock(&NLCacheLock);
    NSNumber *cached = [NLTransparencyCache objectForKey:image];
    os_unfair_lock_unlock(&NLCacheLock);

    if (cached != nil) {
        return cached.boolValue;
    }

    // Preserve the original 1.1.4 behavior exactly on the first encounter.
    // This is the only call that performs CGBitmapContextCreate + DrawImage +
    // alpha-byte scanning for this UIImage instance.
    BOOL result = NLOriginalHasRealTransparency(image);

    os_unfair_lock_lock(&NLCacheLock);
    [NLTransparencyCache setObject:@(result) forKey:image];
    os_unfair_lock_unlock(&NLCacheLock);

    return result;
}

static BOOL NLFindUUIDAndOffset(const struct mach_header *mh,
                                uintptr_t *offsetOut,
                                const char **archOut) {
    if (mh == NULL || offsetOut == NULL) {
        return NO;
    }

    const uint8_t *uuid = NULL;
    uint32_t ncmds = 0;
    const uint8_t *cursor = NULL;

    if (mh->magic == MH_MAGIC_64) {
        const struct mach_header_64 *h64 = (const struct mach_header_64 *)mh;
        ncmds = h64->ncmds;
        cursor = (const uint8_t *)(h64 + 1);
    } else {
        return NO;
    }

    for (uint32_t i = 0; i < ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(struct load_command)) {
            return NO;
        }

        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uc = (const struct uuid_command *)lc;
            uuid = uc->uuid;
            break;
        }
        cursor += lc->cmdsize;
    }

    if (uuid == NULL) {
        return NO;
    }

    if (memcmp(uuid, kNextLock114Arm64UUID, sizeof(kNextLock114Arm64UUID)) == 0) {
        *offsetOut = kNextLock114Arm64TransparencyOffset;
        if (archOut) *archOut = "arm64";
        return YES;
    }

    if (memcmp(uuid, kNextLock114Arm64eUUID, sizeof(kNextLock114Arm64eUUID)) == 0) {
        *offsetOut = kNextLock114Arm64eTransparencyOffset;
        if (archOut) *archOut = "arm64e";
        return YES;
    }

    return NO;
}

static void NLInstallHook(const struct mach_header *mh,
                          uintptr_t helperOffset,
                          const char *matchedArch) {
    os_unfair_lock_lock(&NLInstallLock);
    if (NLHookInstalled) {
        os_unfair_lock_unlock(&NLInstallLock);
        return;
    }

    // LockGlyphTime's __TEXT vmaddr is zero, so the loaded Mach header is the
    // image base and the verified helper offset can be added directly.
    void *target = (void *)((uintptr_t)mh + helperOffset);
    MSHookFunction(target,
                   (void *)&NLCachedHasRealTransparency,
                   (void **)&NLOriginalHasRealTransparency);

    if (NLOriginalHasRealTransparency != NULL) {
        NLHookInstalled = YES;
        NSLog(@"[NextLockPerfFix] exact transparency cache installed (%s, +0x%lx)",
              matchedArch ?: "unknown",
              (unsigned long)helperOffset);
    }
    os_unfair_lock_unlock(&NLInstallLock);
}

static void NLImageAdded(const struct mach_header *mh, intptr_t vmaddrSlide) {
    (void)vmaddrSlide;

    uintptr_t helperOffset = 0;
    const char *matchedArch = NULL;
    if (!NLFindUUIDAndOffset(mh, &helperOffset, &matchedArch)) {
        return;
    }

    // Do not patch code while executing inside dyld's add-image callback.
    // The image remains loaded, so scheduling the actual Substrate hook onto
    // SpringBoard's main queue is safe and removes loader-lock/reentrancy risk.
    dispatch_async(dispatch_get_main_queue(), ^{
        NLInstallHook(mh, helperOffset, matchedArch);
    });
}

__attribute__((constructor))
static void NLPerfFixInit(void) {
    @autoreleasepool {
        // dyld immediately reports already-loaded images and also calls us if
        // LockGlyphTime loads after this companion dylib, eliminating load-order
        // dependence without touching any SpringBoard/UI methods.
        _dyld_register_func_for_add_image(NLImageAdded);
    }
}
