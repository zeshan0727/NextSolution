#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <os/lock.h>
#include <string.h>

extern void MSHookFunction(void *symbol, void *replace, void **result);

// NextLock 1.1.4 LockGlyphTime.dylib UUIDs and offsets verified from the exact
// live universal binary captured from the affected device.
//
// arm64 : C7EBC4D1-EAD4-3320-A27F-34E86C25F776
//   transparency helper     +0xAE18
//   deferred render block   +0x998C
//   synchronous renderer    +0x896C
//   layout hook replacement +0x6510
//
// arm64e: 7BE1428A-C4B0-38F8-8120-7BACBF220731
//   transparency helper     +0xAF74
//   deferred render block   +0x9A7C
//   synchronous renderer    +0x8A58
//   layout hook replacement +0x6574
//
// Static analysis of 1.1.4 shows the layout hook does all rendering
// synchronously and then dispatch_async()s a block to the main queue whose only
// operation is to call the exact same full renderer again on the same host.
// That second pass is redundant and can create a layout/render feedback cycle
// because the renderer changes frames/text/images. Test 3 removes ONLY that
// duplicate deferred pass. The synchronous renderer, all normal layout logic,
// timer refreshes, preference reloads, clock/date styling and all four image
// frames remain untouched.
//
// We also retain Test 1's exact-result transparency memoization so the original
// expensive alpha scan is executed only once per stable UIImage instance.

static const uint8_t kNextLock114Arm64UUID[16] = {
    0xC7, 0xEB, 0xC4, 0xD1, 0xEA, 0xD4, 0x33, 0x20,
    0xA2, 0x7F, 0x34, 0xE8, 0x6C, 0x25, 0xF7, 0x76
};

static const uint8_t kNextLock114Arm64eUUID[16] = {
    0x7B, 0xE1, 0x42, 0x8A, 0xC4, 0xB0, 0x38, 0xF8,
    0x81, 0x20, 0x7B, 0xAC, 0xBF, 0x22, 0x07, 0x31
};

static const uintptr_t kArm64TransparencyOffset  = 0xAE18;
static const uintptr_t kArm64DeferredBlockOffset = 0x998C;
static const uintptr_t kArm64eTransparencyOffset  = 0xAF74;
static const uintptr_t kArm64eDeferredBlockOffset = 0x9A7C;

static BOOL (*NLOriginalHasRealTransparency)(UIImage *image) = NULL;
static void (*NLOriginalDeferredRenderBlock)(void *blockObject) = NULL;

static NSMapTable<UIImage *, NSNumber *> *NLTransparencyCache = nil;
static os_unfair_lock NLCacheLock = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock NLInstallLock = OS_UNFAIR_LOCK_INIT;
static BOOL NLInstalled = NO;

__attribute__((used)) static const char *NLPerfFixMarker =
    "NextLockPerfFix 1.1.5-test3 remove-duplicate-deferred-render exact-transparency-cache";

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

    // Exact 1.1.4 behavior on the first encounter.
    BOOL result = NLOriginalHasRealTransparency(image);

    os_unfair_lock_lock(&NLCacheLock);
    [NLTransparencyCache setObject:@(result) forKey:image];
    os_unfair_lock_unlock(&NLCacheLock);
    return result;
}

// This is the block implementation queued by the 1.1.4 layout hook *after* it
// has already completed the same full render synchronously. Returning here does
// not remove any feature; it only removes the redundant second pass.
static void NLSuppressDuplicateDeferredRender(void *blockObject) {
    (void)blockObject;
}

static BOOL NLFindUUIDAndOffsets(const struct mach_header *mh,
                                 uintptr_t *transparencyOffset,
                                 uintptr_t *deferredOffset,
                                 const char **archName) {
    if (mh == NULL || transparencyOffset == NULL || deferredOffset == NULL) {
        return NO;
    }

    if (mh->magic != MH_MAGIC_64) {
        return NO;
    }

    const struct mach_header_64 *h64 = (const struct mach_header_64 *)mh;
    const uint8_t *cursor = (const uint8_t *)(h64 + 1);
    const uint8_t *uuid = NULL;

    for (uint32_t i = 0; i < h64->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(struct load_command)) {
            return NO;
        }
        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            uuid = ((const struct uuid_command *)lc)->uuid;
            break;
        }
        cursor += lc->cmdsize;
    }

    if (uuid == NULL) {
        return NO;
    }

    if (memcmp(uuid, kNextLock114Arm64UUID, 16) == 0) {
        *transparencyOffset = kArm64TransparencyOffset;
        *deferredOffset = kArm64DeferredBlockOffset;
        if (archName) *archName = "arm64";
        return YES;
    }

    if (memcmp(uuid, kNextLock114Arm64eUUID, 16) == 0) {
        *transparencyOffset = kArm64eTransparencyOffset;
        *deferredOffset = kArm64eDeferredBlockOffset;
        if (archName) *archName = "arm64e";
        return YES;
    }

    return NO;
}

static void NLInstallHooks(const struct mach_header *mh,
                           uintptr_t transparencyOffset,
                           uintptr_t deferredOffset,
                           const char *archName) {
    os_unfair_lock_lock(&NLInstallLock);
    if (NLInstalled) {
        os_unfair_lock_unlock(&NLInstallLock);
        return;
    }

    void *transparencyTarget = (void *)((uintptr_t)mh + transparencyOffset);
    void *deferredTarget = (void *)((uintptr_t)mh + deferredOffset);

    MSHookFunction(transparencyTarget,
                   (void *)&NLCachedHasRealTransparency,
                   (void **)&NLOriginalHasRealTransparency);

    MSHookFunction(deferredTarget,
                   (void *)&NLSuppressDuplicateDeferredRender,
                   (void **)&NLOriginalDeferredRenderBlock);

    if (NLOriginalHasRealTransparency != NULL &&
        NLOriginalDeferredRenderBlock != NULL) {
        NLInstalled = YES;
        NSLog(@"[NextLockPerfFix] Test3 installed (%s): transparency +0x%lx, duplicate deferred render +0x%lx suppressed",
              archName ?: "unknown",
              (unsigned long)transparencyOffset,
              (unsigned long)deferredOffset);
    }

    os_unfair_lock_unlock(&NLInstallLock);
}

static void NLImageAdded(const struct mach_header *mh, intptr_t vmaddrSlide) {
    (void)vmaddrSlide;

    uintptr_t transparencyOffset = 0;
    uintptr_t deferredOffset = 0;
    const char *archName = NULL;
    if (!NLFindUUIDAndOffsets(mh, &transparencyOffset, &deferredOffset, &archName)) {
        return;
    }

    // Avoid patching while inside dyld's image callback.
    dispatch_async(dispatch_get_main_queue(), ^{
        NLInstallHooks(mh, transparencyOffset, deferredOffset, archName);
    });
}

__attribute__((constructor))
static void NLPerfFixInit(void) {
    @autoreleasepool {
        _dyld_register_func_for_add_image(NLImageAdded);
    }
}
