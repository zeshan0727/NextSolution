#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <os/lock.h>
#import <objc/runtime.h>
#include <string.h>

extern void MSHookFunction(void *symbol, void *replace, void **result);
extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

// -----------------------------------------------------------------------------
// Verified NextLock 1.1.4 runtime offsets / UUID gates
// -----------------------------------------------------------------------------
static const uint8_t kNextLock114Arm64UUID[16] = {
    0xC7, 0xEB, 0xC4, 0xD1, 0xEA, 0xD4, 0x33, 0x20,
    0xA2, 0x7F, 0x34, 0xE8, 0x6C, 0x25, 0xF7, 0x76
};
static const uint8_t kNextLock114Arm64eUUID[16] = {
    0x7B, 0xE1, 0x42, 0x8A, 0xC4, 0xB0, 0x38, 0xF8,
    0x81, 0x20, 0x7B, 0xAC, 0xBF, 0x22, 0x07, 0x31
};

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

// Test 7 keeps the live-proven Test 5 CPU strategy: suppress only the redundant
// 120 Hz callback and the duplicate deferred render. Normal layout/render code
// stays unthrottled so time/date/photo position controls remain functional.
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

static BOOL NLPhotoCaptureActive = NO;
static NSUInteger NLActiveFrameIndices[4] = {0, 0, 0, 0};
static NSUInteger NLActiveFrameCount = 0;
static NSUInteger NLContentModeOrdinal = 0;
static __unsafe_unretained UIImageView *NLCapturedViews[4] = {nil, nil, nil, nil};

__attribute__((used)) static const char *NLPerfFixMarker =
    "NextLockPerfFix 1.1.5-test7 refined-full-photo 2048px test5-cpu auto-stretch-full-cutcrop";

// -----------------------------------------------------------------------------
// SpringBoard CPU fix + refined frame rendering
// -----------------------------------------------------------------------------
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
        key = CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
                                       CFSTR("customPhotoData%lu"),
                                       (unsigned long)(index + 1));
    }
    CFTypeRef value = CFPreferencesCopyAppValue(key, CFSTR("com.nextsolution.lockglyphtime"));
    CFRelease(key);
    if (value == NULL) return NO;
    BOOL exists = (CFGetTypeID(value) == CFDataGetTypeID() &&
                   CFDataGetLength((CFDataRef)value) > 0);
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

static void NLApplyHighQualityLayerSettings(UIImageView *view) {
    if (view == nil) return;
    view.layer.minificationFilter = kCAFilterTrilinear;
    view.layer.magnificationFilter = kCAFilterLinear;
    view.layer.contentsScale = [UIScreen mainScreen].scale;
    view.layer.shouldRasterize = NO;
    view.layer.allowsEdgeAntialiasing = YES;
}

static void NLApplyPhotoModeToView(UIImageView *view, NSInteger mode) {
    if (view == nil) return;
    NLApplyHighQualityLayerSettings(view);
    if (mode == 0) return;

    switch (mode) {
        case 1: // Stretch
            view.contentMode = UIViewContentModeScaleToFill;
            view.clipsToBounds = YES;
            break;
        case 2: // Full Photo - show the entire preserved source image
            view.contentMode = UIViewContentModeScaleAspectFit;
            view.maskView = nil;
            view.layer.mask = nil;
            view.layer.cornerRadius = 0.0;
            view.clipsToBounds = YES;
            break;
        case 3: // Cut / Crop - fill the frame without distortion
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

    for (NSUInteger i = 0; i < 4; i++) {
        if (NLCapturedViews[i] != nil) {
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

static void NLInstallSpringBoardHooks(const struct mach_header *mh) {
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
        NSLog(@"[NextLockPerfFix] Test7 SpringBoard hooks installed (%s): Test5 CPU fix + refined photo modes",
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
        NLInstallSpringBoardHooks(mh);
    });
}

// -----------------------------------------------------------------------------
// Settings / PreferenceBundle refined picker
// -----------------------------------------------------------------------------
// NextLock 1.1.4's original LGTPhotoCropController hard-crops the selected image
// to the visible square and then renders it into a 512x512 context. That destroys
// the rest of the photo and limits detail before SpringBoard ever sees it.
// Test 7 keeps the whole photo visible in the selector and stores the full aspect
// image at up to 2048 pixels on the longest side with high-quality interpolation.

@protocol NLPhotoCropAPI <NSObject>
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, copy) void (^completion)(UIImage *image);
- (UIImage *)normalizedImage:(UIImage *)image;
@end

static void (*NLOriginalCropViewDidLoad)(id self, SEL _cmd) = NULL;
static void (*NLOriginalCropViewDidLayoutSubviews)(id self, SEL _cmd) = NULL;
static void (*NLOriginalCropUsePhoto)(id self, SEL _cmd) = NULL;
static os_unfair_lock NLPrefsInstallLock = OS_UNFAIR_LOCK_INIT;
static BOOL NLPrefsHooksInstalled = NO;
static id NLBundleLoadObserver = nil;
static char kNLRefinedPickerAssociationKey;
static const NSInteger kNLInfoLabelTag = 0x4E4C3701;

static UIImage *NLHighQualityWholePhoto(UIImage *image) {
    if (image == nil) return nil;

    size_t pixelWidth = image.CGImage ? CGImageGetWidth(image.CGImage) : (size_t)llround(image.size.width * image.scale);
    size_t pixelHeight = image.CGImage ? CGImageGetHeight(image.CGImage) : (size_t)llround(image.size.height * image.scale);
    if (pixelWidth == 0 || pixelHeight == 0) return image;

    const CGFloat maxLongEdge = 2048.0;
    CGFloat longest = (CGFloat)MAX(pixelWidth, pixelHeight);
    if (longest <= maxLongEdge) return image;

    CGFloat ratio = maxLongEdge / longest;
    CGSize target = CGSizeMake(MAX(1.0, round((CGFloat)pixelWidth * ratio)),
                               MAX(1.0, round((CGFloat)pixelHeight * ratio)));

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        CGContextSetInterpolationQuality(context.CGContext, kCGInterpolationHigh);
        CGContextSetShouldAntialias(context.CGContext, true);
        [image drawInRect:(CGRect){CGPointZero, target}];
    }];
    return result ?: image;
}

static BOOL NLPickerIsRefined(id self) {
    NSNumber *n = objc_getAssociatedObject(self, &kNLRefinedPickerAssociationKey);
    return n.boolValue;
}

static void NLRefinedCropViewDidLoad(id self, SEL _cmd) {
    if (NLOriginalCropViewDidLoad != NULL) {
        NLOriginalCropViewDidLoad(self, _cmd);
    }

    UIViewController *controller = (UIViewController *)self;
    id<NLPhotoCropAPI> crop = (id<NLPhotoCropAPI>)self;
    UIView *root = controller.view;
    if (root == nil) return;

    // Remove the old square crop canvas. Keep the navigation bar/buttons created
    // by the original controller, including Cancel and Use Photo.
    NSArray<UIView *> *oldSubviews = [root.subviews copy];
    for (UIView *subview in oldSubviews) {
        [subview removeFromSuperview];
    }

    controller.title = @"Photo Preview";
    root.backgroundColor = [UIColor systemBackgroundColor];

    UILabel *info = [[UILabel alloc] initWithFrame:CGRectZero];
    info.tag = kNLInfoLabelTag;
    info.numberOfLines = 0;
    info.textAlignment = NSTextAlignmentCenter;
    info.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    info.textColor = [UIColor secondaryLabelColor];
    info.text = @"The complete original photo is preserved. Nothing is square-cropped here. Use Photo saves the full image; Auto / Stretch / Full Photo / Cut-Crop controls how it appears on the Lock Screen.";
    [root addSubview:info];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.backgroundColor = [UIColor secondarySystemBackgroundColor];
    scroll.delegate = (id<UIScrollViewDelegate>)self;
    scroll.minimumZoomScale = 1.0;
    scroll.maximumZoomScale = 6.0;
    scroll.zoomScale = 1.0;
    scroll.bouncesZoom = YES;
    scroll.clipsToBounds = YES;
    scroll.layer.cornerRadius = 14.0;
    if (@available(iOS 13.0, *)) {
        scroll.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [root addSubview:scroll];

    UIImageView *imageView = [[UIImageView alloc] initWithImage:crop.image];
    imageView.backgroundColor = [UIColor clearColor];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.clipsToBounds = YES;
    NLApplyHighQualityLayerSettings(imageView);
    [scroll addSubview:imageView];

    crop.scrollView = scroll;
    crop.imageView = imageView;
    objc_setAssociatedObject(self, &kNLRefinedPickerAssociationKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [controller.view setNeedsLayout];
}

static void NLRefinedCropViewDidLayoutSubviews(id self, SEL _cmd) {
    if (!NLPickerIsRefined(self)) {
        if (NLOriginalCropViewDidLayoutSubviews != NULL) {
            NLOriginalCropViewDidLayoutSubviews(self, _cmd);
        }
        return;
    }

    UIViewController *controller = (UIViewController *)self;
    id<NLPhotoCropAPI> crop = (id<NLPhotoCropAPI>)self;
    UIView *root = controller.view;
    UILabel *info = (UILabel *)[root viewWithTag:kNLInfoLabelTag];
    UIScrollView *scroll = crop.scrollView;
    UIImageView *imageView = crop.imageView;
    if (root == nil || scroll == nil || imageView == nil) return;

    UIEdgeInsets safe = root.safeAreaInsets;
    CGFloat horizontal = 14.0;
    CGFloat top = safe.top + 10.0;
    CGFloat availableWidth = MAX(1.0, CGRectGetWidth(root.bounds) - horizontal * 2.0);
    CGFloat infoHeight = 70.0;
    info.frame = CGRectMake(horizontal, top, availableWidth, infoHeight);

    CGFloat scrollTop = CGRectGetMaxY(info.frame) + 10.0;
    CGFloat bottom = safe.bottom + 12.0;
    CGFloat scrollHeight = MAX(120.0, CGRectGetHeight(root.bounds) - scrollTop - bottom);
    CGRect desiredScrollFrame = CGRectMake(horizontal, scrollTop, availableWidth, scrollHeight);

    BOOL frameChanged = !CGRectEqualToRect(scroll.frame, desiredScrollFrame);
    scroll.frame = desiredScrollFrame;

    if (frameChanged || scroll.zoomScale <= scroll.minimumZoomScale + 0.001) {
        scroll.zoomScale = 1.0;
        imageView.transform = CGAffineTransformIdentity;
        imageView.frame = scroll.bounds;
        scroll.contentSize = scroll.bounds.size;
        scroll.contentOffset = CGPointZero;
    }
}

static void NLRefinedCropUsePhoto(id self, SEL _cmd) {
    if (!NLPickerIsRefined(self)) {
        if (NLOriginalCropUsePhoto != NULL) NLOriginalCropUsePhoto(self, _cmd);
        return;
    }

    id<NLPhotoCropAPI> crop = (id<NLPhotoCropAPI>)self;
    UIImage *source = crop.image;
    UIImage *normalized = source;
    if (source != nil && [self respondsToSelector:@selector(normalizedImage:)]) {
        normalized = [crop normalizedImage:source] ?: source;
    }

    UIImage *prepared = NLHighQualityWholePhoto(normalized);
    void (^completion)(UIImage *) = crop.completion;
    if (completion != nil && prepared != nil) {
        completion(prepared);
    }

    UIViewController *controller = (UIViewController *)self;
    UINavigationController *nav = controller.navigationController;
    if (nav.presentingViewController != nil) {
        [nav dismissViewControllerAnimated:YES completion:nil];
    } else if (controller.presentingViewController != nil) {
        [controller dismissViewControllerAnimated:YES completion:nil];
    } else if (nav != nil) {
        [nav popViewControllerAnimated:YES];
    }
}

static void NLInstallPreferenceHooksIfAvailable(void) {
    os_unfair_lock_lock(&NLPrefsInstallLock);
    if (NLPrefsHooksInstalled) {
        os_unfair_lock_unlock(&NLPrefsInstallLock);
        return;
    }

    Class cropClass = objc_getClass("LGTPhotoCropController");
    if (cropClass == Nil) {
        os_unfair_lock_unlock(&NLPrefsInstallLock);
        return;
    }

    MSHookMessageEx(cropClass,
                    @selector(viewDidLoad),
                    (IMP)&NLRefinedCropViewDidLoad,
                    (IMP *)&NLOriginalCropViewDidLoad);
    MSHookMessageEx(cropClass,
                    @selector(viewDidLayoutSubviews),
                    (IMP)&NLRefinedCropViewDidLayoutSubviews,
                    (IMP *)&NLOriginalCropViewDidLayoutSubviews);
    MSHookMessageEx(cropClass,
                    @selector(usePhoto),
                    (IMP)&NLRefinedCropUsePhoto,
                    (IMP *)&NLOriginalCropUsePhoto);

    if (NLOriginalCropViewDidLoad != NULL &&
        NLOriginalCropViewDidLayoutSubviews != NULL &&
        NLOriginalCropUsePhoto != NULL) {
        NLPrefsHooksInstalled = YES;
        NSLog(@"[NextLockPerfFix] Test7 refined full-photo picker installed");
    }
    os_unfair_lock_unlock(&NLPrefsInstallLock);
}

static void NLStartPreferenceBundleWatcher(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NLInstallPreferenceHooksIfAvailable();
        if (NLBundleLoadObserver == nil) {
            NLBundleLoadObserver = [[NSNotificationCenter defaultCenter]
                addObserverForName:NSBundleDidLoadNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(__unused NSNotification *note) {
                            NLInstallPreferenceHooksIfAvailable();
                        }];
        }
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
        NLStartPreferenceBundleWatcher();
    }
}
