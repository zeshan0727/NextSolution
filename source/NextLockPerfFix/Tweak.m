#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
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
static const uintptr_t kArm64TransparencyOffset    = 0xAE18;
static const uintptr_t kArm64DeferredBlockOffset   = 0x998C;
static const uintptr_t kArm64CallbackBlockOffset   = 0xBC30;
static const uintptr_t kArm64PhotosOffset          = 0x896C;
static const uintptr_t kArm64SetContentModeStub    = 0xD7C0;

static const uintptr_t kArm64eTransparencyOffset   = 0xAF74;
static const uintptr_t kArm64eDeferredBlockOffset  = 0x9A7C;
static const uintptr_t kArm64eCallbackBlockOffset  = 0xBDD4;
static const uintptr_t kArm64ePhotosOffset         = 0x8A58;
static const uintptr_t kArm64eSetContentModeStub   = 0xDAE0;

// Test 5 CPU fix: live caller counting proved the callback block executes at
// 120 Hz and redundantly calls updateA + the photo renderer. Suppress only that
// callback while leaving normal layout/update functions untouched.
//
// Photo content-mode feature: the original four-frame loop calls the dedicated
// LockGlyphTime setContentMode: objc stub exactly once for each enabled frame
// that has a decoded image. We wrap the original photo renderer only to capture
// those UIImageView receivers, then apply a user-selected final mode after the
// original renderer has completed. No original geometry/anchor/position code is
// skipped or throttled.

static BOOL (*NLOriginalHasRealTransparency)(UIImage *image) = NULL;
static void (*NLOriginalDeferredRenderBlock)(void *blockObject) = NULL;
static void (*NLOriginalHotCallbackBlock)(void *blockObject) = NULL;
static void (*NLOriginalPhotos)(id host) = NULL;
static void (*NLOriginalSetContentModeStub)(id receiver, void *unusedX1, NSInteger mode) = NULL;

static NSMapTable<UIImage *, NSNumber *> *NLTransparencyCache = nil;
static os_unfair_lock NLCacheLock = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock NLInstallLock = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock NLModeLock = OS_UNFAIR_LOCK_INIT;
static BOOL NLInstalled = NO;

// 0 = Auto/current NextLock behavior
// 1 = Stretch (ScaleToFill)
// 2 = Full Photo (ScaleAspectFit)
// 3 = Cut / Crop (ScaleAspectFill)
static NSInteger NLPhotoModes[4] = {0, 0, 0, 0};
static BOOL NLFrameEnabled[4] = {NO, NO, NO, NO};
static BOOL NLFrameHasPhoto[4] = {NO, NO, NO, NO};

// Renderer capture state. The renderer runs on SpringBoard's UI thread.
static BOOL NLPhotoCaptureActive = NO;
static NSUInteger NLActiveFrameIndices[4] = {0, 0, 0, 0};
static NSUInteger NLActiveFrameCount = 0;
static NSUInteger NLContentModeOrdinal = 0;
static __unsafe_unretained UIImageView *NLCapturedViews[4] = {nil, nil, nil, nil};

__attribute__((used)) static const char *NLPerfFixMarker =
    "NextLockPerfFix 1.1.5-photo-modes test5-cpu preserve-layout auto-stretch-full-cutout";

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

static void NLSuppressDuplicateDeferredRender(void *blockObject) {
    (void)blockObject;
}

static void NLSuppressHotCallback(void *blockObject) {
    (void)blockObject;
}

static NSInteger NLCopyIntegerPref(CFStringRef key, NSInteger fallback) {
    CFTypeRef value = CFPreferencesCopyAppValue(key, CFSTR("com.nextsolution.lockglyphtime"));
    if (value == NULL) return fallback;
    NSInteger result = fallback;
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)value, kCFNumberNSIntegerType, &result);
    } else if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value) ? 1 : 0;
    }
    CFRelease(value);
    return result;
}

static BOOL NLCopyBoolPref(CFStringRef key, BOOL fallback) {
    CFTypeRef value = CFPreferencesCopyAppValue(key, CFSTR("com.nextsolution.lockglyphtime"));
    if (value == NULL) return fallback;
    BOOL result = fallback;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value);
    } else if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        int n = 0;
        CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &n);
        result = n != 0;
    }
    CFRelease(value);
    return result;
}

static BOOL NLPhotoDataExistsForFrame(NSUInteger index) {
    CFStringRef key = NULL;
    if (index == 0) {
        key = CFSTR("customPhotoData");
        CFRetain(key);
    } else {
        key = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("customPhotoData%lu"), (unsigned long)(index + 1));
    }
    CFTypeRef value = CFPreferencesCopyAppValue(key, CFSTR("com.nextsolution.lockglyphtime"));
    CFRelease(key);
    if (value == NULL) return NO;
    BOOL exists = NO;
    if (CFGetTypeID(value) == CFDataGetTypeID()) {
        exists = CFDataGetLength((CFDataRef)value) > 0;
    }
    CFRelease(value);
    return exists;
}

static void NLReloadPhotoModePrefs(void) {
    CFPreferencesAppSynchronize(CFSTR("com.nextsolution.lockglyphtime"));
    NSInteger modes[4] = {0, 0, 0, 0};
    BOOL enabled[4] = {NO, NO, NO, NO};
    BOOL hasPhoto[4] = {NO, NO, NO, NO};

    for (NSUInteger i = 0; i < 4; i++) {
        CFStringRef modeKey = CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
                                                       CFSTR("photoFrame%luContentMode"),
                                                       (unsigned long)(i + 1));
        CFStringRef enabledKey = CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
                                                          CFSTR("photoFrame%luEnabled"),
                                                          (unsigned long)(i + 1));
        NSInteger mode = NLCopyIntegerPref(modeKey, 0);
        if (mode < 0 || mode > 3) mode = 0;
        modes[i] = mode;
        enabled[i] = NLCopyBoolPref(enabledKey, NO);
        hasPhoto[i] = NLPhotoDataExistsForFrame(i);
        CFRelease(modeKey);
        CFRelease(enabledKey);
    }

    os_unfair_lock_lock(&NLModeLock);
    for (NSUInteger i = 0; i < 4; i++) {
        NLPhotoModes[i] = modes[i];
        NLFrameEnabled[i] = enabled[i];
        NLFrameHasPhoto[i] = hasPhoto[i];
    }
    os_unfair_lock_unlock(&NLModeLock);
}

static void NLPrefsChanged(CFNotificationCenterRef center,
                           void *observer,
                           CFStringRef name,
                           const void *object,
                           CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    NLReloadPhotoModePrefs();
}

static void NLSetContentModeCapture(id receiver, void *unusedX1, NSInteger mode) {
    if (NLPhotoCaptureActive && NLContentModeOrdinal < NLActiveFrameCount) {
        NSUInteger frameIndex = NLActiveFrameIndices[NLContentModeOrdinal++];
        if (frameIndex < 4 && [receiver isKindOfClass:[UIImageView class]]) {
            NLCapturedViews[frameIndex] = (UIImageView *)receiver;
        }
    }

    if (NLOriginalSetContentModeStub != NULL) {
        NLOriginalSetContentModeStub(receiver, unusedX1, mode);
    }
}

static void NLApplyPhotoModeToView(UIImageView *view, NSInteger mode) {
    if (view == nil || mode == 0) return;

    switch (mode) {
        case 1: // Stretch
            view.contentMode = UIViewContentModeScaleToFill;
            view.clipsToBounds = YES;
            break;
        case 2: // Full photo
            view.contentMode = UIViewContentModeScaleAspectFit;
            // Do not let a rounded opaque-photo mask cut off the full image.
            view.clipsToBounds = NO;
            break;
        case 3: // Cut / crop
            view.contentMode = UIViewContentModeScaleAspectFill;
            view.clipsToBounds = YES;
            break;
        default:
            break;
    }
}

static void NLPhotosWithContentModes(id host) {
    if (NLOriginalPhotos == NULL) return;

    NSInteger modes[4] = {0, 0, 0, 0};
    BOOL enabled[4] = {NO, NO, NO, NO};
    BOOL hasPhoto[4] = {NO, NO, NO, NO};

    os_unfair_lock_lock(&NLModeLock);
    for (NSUInteger i = 0; i < 4; i++) {
        modes[i] = NLPhotoModes[i];
        enabled[i] = NLFrameEnabled[i];
        hasPhoto[i] = NLFrameHasPhoto[i];
    }
    os_unfair_lock_unlock(&NLModeLock);

    NLActiveFrameCount = 0;
    NLContentModeOrdinal = 0;
    for (NSUInteger i = 0; i < 4; i++) {
        NLCapturedViews[i] = nil;
        if (enabled[i] && hasPhoto[i]) {
            NLActiveFrameIndices[NLActiveFrameCount++] = i;
        }
    }

    NLPhotoCaptureActive = YES;
    NLOriginalPhotos(host);
    NLPhotoCaptureActive = NO;

    // Re-apply only explicit user overrides. Auto mode remains byte-for-byte
    // equivalent to the original NextLock transparency-aware behavior.
    for (NSUInteger i = 0; i < 4; i++) {
        if (modes[i] != 0 && NLCapturedViews[i] != nil) {
            NLApplyPhotoModeToView(NLCapturedViews[i], modes[i]);
        }
    }
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
    uintptr_t photosOffset = isArm64e ? kArm64ePhotosOffset : kArm64PhotosOffset;
    uintptr_t contentModeStub = isArm64e ? kArm64eSetContentModeStub : kArm64SetContentModeStub;

    MSHookFunction((void *)((uintptr_t)mh + transparencyOffset),
                   (void *)&NLCachedHasRealTransparency,
                   (void **)&NLOriginalHasRealTransparency);

    MSHookFunction((void *)((uintptr_t)mh + deferredOffset),
                   (void *)&NLSuppressDuplicateDeferredRender,
                   (void **)&NLOriginalDeferredRenderBlock);

    MSHookFunction((void *)((uintptr_t)mh + callbackOffset),
                   (void *)&NLSuppressHotCallback,
                   (void **)&NLOriginalHotCallbackBlock);

    MSHookFunction((void *)((uintptr_t)mh + contentModeStub),
                   (void *)&NLSetContentModeCapture,
                   (void **)&NLOriginalSetContentModeStub);

    MSHookFunction((void *)((uintptr_t)mh + photosOffset),
                   (void *)&NLPhotosWithContentModes,
                   (void **)&NLOriginalPhotos);

    if (NLOriginalHasRealTransparency != NULL &&
        NLOriginalDeferredRenderBlock != NULL &&
        NLOriginalHotCallbackBlock != NULL &&
        NLOriginalSetContentModeStub != NULL &&
        NLOriginalPhotos != NULL) {
        NLInstalled = YES;
        NSLog(@"[NextLockPerfFix] photo modes installed (%s): Test5 CPU path + Auto/Stretch/Full/Cut-Out per frame",
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
        NLReloadPhotoModePrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        NLPrefsChanged,
                                        CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        _dyld_register_func_for_add_image(NLImageAdded);
    }
}
