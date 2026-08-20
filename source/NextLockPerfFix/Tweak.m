#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <os/lock.h>
#include <string.h>

extern void MSHookFunction(void *symbol, void *replace, void **result);

// Exact NextLock 1.1.4 UUIDs captured from the affected device.
static const uint8_t kNextLock114Arm64UUID[16] = {
    0xC7, 0xEB, 0xC4, 0xD1, 0xEA, 0xD4, 0x33, 0x20,
    0xA2, 0x7F, 0x34, 0xE8, 0x6C, 0x25, 0xF7, 0x76
};
static const uint8_t kNextLock114Arm64eUUID[16] = {
    0x7B, 0xE1, 0x42, 0x8A, 0xC4, 0xB0, 0x38, 0xF8,
    0x81, 0x20, 0x7B, 0xAC, 0xBF, 0x22, 0x07, 0x31
};

// Verified 1.1.4 offsets.
static const uintptr_t kArm64TransparencyOffset   = 0xAE18;
static const uintptr_t kArm64DeferredBlockOffset  = 0x998C;
static const uintptr_t kArm64CallbackBlockOffset  = 0xBC30;
static const uintptr_t kArm64eTransparencyOffset  = 0xAF74;
static const uintptr_t kArm64eDeferredBlockOffset = 0x9A7C;
static const uintptr_t kArm64eCallbackBlockOffset = 0xBDD4;

// Live caller counting on the affected arm64e device proved that the callback
// block at +0xBDD4 was executing at 120 Hz and calling updateA + photos every
// time, while normal layoutSubviews independently called updateA/updateB/photos
// at 60 Hz. Test 4 throttled the update functions themselves and fixed CPU, but
// that also broke position controls because UIKit could overwrite the frame
// between throttled passes. Test 5 leaves every renderer/update function fully
// intact and suppresses only the redundant 120 Hz callback block. Normal layout,
// global refresh, preference changes and all feature code continue unthrottled.

static BOOL (*NLOriginalHasRealTransparency)(UIImage *image) = NULL;
static void (*NLOriginalDeferredRenderBlock)(void *blockObject) = NULL;
static void (*NLOriginalHotCallbackBlock)(void *blockObject) = NULL;

static NSMapTable<UIImage *, NSNumber *> *NLTransparencyCache = nil;
static os_unfair_lock NLCacheLock = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock NLInstallLock = OS_UNFAIR_LOCK_INIT;
static BOOL NLInstalled = NO;

__attribute__((used)) static const char *NLPerfFixMarker =
    "NextLockPerfFix 1.1.5-test5 suppress-120hz-callback preserve-layout exact-transparency-cache";

static void NLEnsureCache(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NLTransparencyCache = [[NSMapTable alloc]
            initWithKeyOptions:(NSPointerFunctionsWeakMemory |
                                NSPointerFunctionsObjectPointerPersonality)
            valueOptions:NSPointerFunctionsStrongMemory
            capacity:8];
    });
}

static BOOL NLCachedHasRealTransparency(UIImage *image) {
    if (image == nil || NLOriginalHasRealTransparency == NULL) return NO;
    NLEnsureCache();

    os_unfair_lock_lock(&NLCacheLock);
    NSNumber *cached = [NLTransparencyCache objectForKey:image];
    os_unfair_lock_unlock(&NLCacheLock);
    if (cached != nil) return cached.boolValue;

    BOOL result = NLOriginalHasRealTransparency(image);

    os_unfair_lock_lock(&NLCacheLock);
    [NLTransparencyCache setObject:@(result) forKey:image];
    os_unfair_lock_unlock(&NLCacheLock);
    return result;
}

// Redundant second full-photo render already performed synchronously by layout.
static void NLSuppressDuplicateDeferredRender(void *blockObject) {
    (void)blockObject;
}

// Proven 120 Hz callback path. The callback does not own the normal layout pass;
// it only weak-loads the same hosts, checks enable flags, and calls updateA/photos
// again. Suppressing it preserves the normal 60 Hz layout path and therefore the
// position/font/date/photo feature semantics that Test 4's global throttling hurt.
static void NLSuppressHotCallback(void *blockObject) {
    (void)blockObject;
}

static BOOL NLReadUUID(const struct mach_header *mh, const uint8_t **uuidOut) {
    if (mh == NULL || uuidOut == NULL || mh->magic != MH_MAGIC_64) return NO;
    const struct mach_header_64 *h64 = (const struct mach_header_64 *)mh;
    const uint8_t *cursor = (const uint8_t *)(h64 + 1);
    for (uint32_t i = 0; i < h64->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(struct load_command)) return NO;
        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            *uuidOut = ((const struct uuid_command *)lc)->uuid;
            return YES;
        }
        cursor += lc->cmdsize;
    }
    return NO;
}

static void NLInstallHooks(const struct mach_header *mh) {
    os_unfair_lock_lock(&NLInstallLock);
    if (NLInstalled) {
        os_unfair_lock_unlock(&NLInstallLock);
        return;
    }

    const uint8_t *uuid = NULL;
    if (!NLReadUUID(mh, &uuid)) {
        os_unfair_lock_unlock(&NLInstallLock);
        return;
    }

    BOOL isArm64 = memcmp(uuid, kNextLock114Arm64UUID, 16) == 0;
    BOOL isArm64e = memcmp(uuid, kNextLock114Arm64eUUID, 16) == 0;
    if (!isArm64 && !isArm64e) {
        os_unfair_lock_unlock(&NLInstallLock);
        return;
    }

    uintptr_t transparencyOffset = isArm64e ? kArm64eTransparencyOffset : kArm64TransparencyOffset;
    uintptr_t deferredOffset = isArm64e ? kArm64eDeferredBlockOffset : kArm64DeferredBlockOffset;
    uintptr_t callbackOffset = isArm64e ? kArm64eCallbackBlockOffset : kArm64CallbackBlockOffset;

    MSHookFunction((void *)((uintptr_t)mh + transparencyOffset),
                   (void *)&NLCachedHasRealTransparency,
                   (void **)&NLOriginalHasRealTransparency);

    MSHookFunction((void *)((uintptr_t)mh + deferredOffset),
                   (void *)&NLSuppressDuplicateDeferredRender,
                   (void **)&NLOriginalDeferredRenderBlock);

    MSHookFunction((void *)((uintptr_t)mh + callbackOffset),
                   (void *)&NLSuppressHotCallback,
                   (void **)&NLOriginalHotCallbackBlock);

    if (NLOriginalHasRealTransparency != NULL &&
        NLOriginalDeferredRenderBlock != NULL &&
        NLOriginalHotCallbackBlock != NULL) {
        NLInstalled = YES;
        NSLog(@"[NextLockPerfFix] Test5 installed (%s): 120Hz callback suppressed; normal layout/render functions untouched",
              isArm64e ? "arm64e" : "arm64");
    }

    os_unfair_lock_unlock(&NLInstallLock);
}

static void NLImageAdded(const struct mach_header *mh, intptr_t vmaddrSlide) {
    (void)vmaddrSlide;
    const uint8_t *uuid = NULL;
    if (!NLReadUUID(mh, &uuid)) return;
    if (memcmp(uuid, kNextLock114Arm64UUID, 16) != 0 &&
        memcmp(uuid, kNextLock114Arm64eUUID, 16) != 0) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        NLInstallHooks(mh);
    });
}

__attribute__((constructor))
static void NLPerfFixInit(void) {
    @autoreleasepool {
        _dyld_register_func_for_add_image(NLImageAdded);
    }
}
