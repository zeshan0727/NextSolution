#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach_time.h>
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
static const uintptr_t kArm64eTransparencyOffset  = 0xAF74;
static const uintptr_t kArm64eDeferredBlockOffset = 0x9A7C;

// Active arm64e update/render entries verified by live caller counting.
// Device evidence showed:
//   updateA: 120/s callback + 60/s layout
//   updateB: 60/s layout
//   photos : 120/s callback + 60/s layout
// These are static styling/layout operations and do not need display-refresh-rate execution.
static const uintptr_t kArm64eUpdateAOffset = 0x8388;
static const uintptr_t kArm64eUpdateBOffset = 0x86B8;
static const uintptr_t kArm64ePhotosOffset  = 0x8A58;

static BOOL (*NLOriginalHasRealTransparency)(UIImage *image) = NULL;
static void (*NLOriginalDeferredRenderBlock)(void *blockObject) = NULL;
static void (*NLOriginalUpdateA)(id host) = NULL;
static void (*NLOriginalUpdateB)(id host) = NULL;
static void (*NLOriginalPhotos)(id host) = NULL;

static NSMapTable<UIImage *, NSNumber *> *NLTransparencyCache = nil;
static os_unfair_lock NLCacheLock = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock NLInstallLock = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock NLRateLock = OS_UNFAIR_LOCK_INIT;
static BOOL NLInstalled = NO;

static uint64_t NLRateIntervalTicks = 0;
static uint64_t NLLastUpdateA = 0;
static uint64_t NLLastUpdateB = 0;
static uint64_t NLLastPhotos = 0;

__attribute__((used)) static const char *NLPerfFixMarker =
    "NextLockPerfFix 1.1.5-test4 cap-hot-refresh-10hz duplicate-deferred-off exact-transparency-cache";

static void NLInitRateInterval(void) {
    mach_timebase_info_data_t info = {0};
    mach_timebase_info(&info);
    if (info.numer == 0 || info.denom == 0) {
        NLRateIntervalTicks = 0;
        return;
    }
    // 100 ms = max 10 executions/second per expensive update function.
    const uint64_t intervalNs = 100000000ULL;
    NLRateIntervalTicks = (intervalNs * (uint64_t)info.denom) / (uint64_t)info.numer;
}

static BOOL NLShouldRun(uint64_t *lastTick) {
    if (lastTick == NULL || NLRateIntervalTicks == 0) return YES;
    const uint64_t now = mach_absolute_time();
    BOOL allowed = NO;
    os_unfair_lock_lock(&NLRateLock);
    if (*lastTick == 0 || now - *lastTick >= NLRateIntervalTicks) {
        *lastTick = now;
        allowed = YES;
    }
    os_unfair_lock_unlock(&NLRateLock);
    return allowed;
}

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

// Test 3 behavior retained: this deferred block only repeats the full photo render
// already completed synchronously during layout.
static void NLSuppressDuplicateDeferredRender(void *blockObject) {
    (void)blockObject;
}

// Test 4: preserve the exact original functions and arguments, but collapse the
// proven 60/120 Hz duplicate refresh storm to at most 10 Hz per function.
// The original UIKit layoutSubviews itself is NOT hooked or throttled.
static void NLRateLimitedUpdateA(id host) {
    if (NLOriginalUpdateA != NULL && NLShouldRun(&NLLastUpdateA)) NLOriginalUpdateA(host);
}
static void NLRateLimitedUpdateB(id host) {
    if (NLOriginalUpdateB != NULL && NLShouldRun(&NLLastUpdateB)) NLOriginalUpdateB(host);
}
static void NLRateLimitedPhotos(id host) {
    if (NLOriginalPhotos != NULL && NLShouldRun(&NLLastPhotos)) NLOriginalPhotos(host);
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

    MSHookFunction((void *)((uintptr_t)mh + transparencyOffset),
                   (void *)&NLCachedHasRealTransparency,
                   (void **)&NLOriginalHasRealTransparency);
    MSHookFunction((void *)((uintptr_t)mh + deferredOffset),
                   (void *)&NLSuppressDuplicateDeferredRender,
                   (void **)&NLOriginalDeferredRenderBlock);

    if (isArm64e) {
        MSHookFunction((void *)((uintptr_t)mh + kArm64eUpdateAOffset),
                       (void *)&NLRateLimitedUpdateA,
                       (void **)&NLOriginalUpdateA);
        MSHookFunction((void *)((uintptr_t)mh + kArm64eUpdateBOffset),
                       (void *)&NLRateLimitedUpdateB,
                       (void **)&NLOriginalUpdateB);
        MSHookFunction((void *)((uintptr_t)mh + kArm64ePhotosOffset),
                       (void *)&NLRateLimitedPhotos,
                       (void **)&NLOriginalPhotos);
    }

    BOOL baseOK = (NLOriginalHasRealTransparency != NULL && NLOriginalDeferredRenderBlock != NULL);
    BOOL rateOK = !isArm64e || (NLOriginalUpdateA != NULL && NLOriginalUpdateB != NULL && NLOriginalPhotos != NULL);
    if (baseOK && rateOK) {
        NLInstalled = YES;
        NSLog(@"[NextLockPerfFix] Test4 installed (%s): 10Hz hot-refresh cap + duplicate deferred suppression + exact transparency cache",
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
        NLInitRateInterval();
        _dyld_register_func_for_add_image(NLImageAdded);
    }
}
