#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface NMAppDelegate : UIResponder <UIApplicationDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIViewController *rootVC;
@property (nonatomic, strong) UIView *canvas;
@property (nonatomic, strong) UIView *phone;
@property (nonatomic, strong) UIImageView *screenshotView;
@property (nonatomic, strong) UIImageView *frameView;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UISlider *scaleSlider;
@property (nonatomic) NSInteger finish;
@property (nonatomic) NSInteger backgroundMode;
@end

@implementation NMAppDelegate

- (UIColor *)colorR:(CGFloat)r g:(CGFloat)g b:(CGFloat)b a:(CGFloat)a {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

- (UILabel *)labelWithFrame:(CGRect)frame text:(NSString *)text size:(CGFloat)size bold:(BOOL)bold color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    label.textColor = color;
    return label;
}

- (UIButton *)buttonWithFrame:(CGRect)frame title:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = [self colorR:0.12 g:0.13 b:0.16 a:0.96];
    button.layer.cornerRadius = 12.0;
    button.clipsToBounds = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (NSString *)frameAssetName {
    if (self.finish == 1) return @"iphone17promax_orange";
    if (self.finish == 2) return @"iphone17promax_blue";
    return @"iphone17promax_silver";
}

- (void)updateFrameAsset {
    self.frameView.image = [UIImage imageNamed:[self frameAssetName]];
}

- (void)setCanvasBackground {
    switch (self.backgroundMode) {
        case 1: self.canvas.backgroundColor = [self colorR:0.96 g:0.96 b:0.98 a:1.0]; break;
        case 2: self.canvas.backgroundColor = [self colorR:0.08 g:0.18 b:0.35 a:1.0]; break;
        default: self.canvas.backgroundColor = [self colorR:0.035 g:0.038 b:0.05 a:1.0]; break;
    }
}

- (void)setStatus:(NSString *)text {
    self.statusLabel.text = text;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application; (void)launchOptions;
    CGRect bounds = UIScreen.mainScreen.bounds;
    CGFloat W = CGRectGetWidth(bounds), H = CGRectGetHeight(bounds);

    self.window = [[UIWindow alloc] initWithFrame:bounds];
    self.rootVC = [UIViewController new];
    UIView *root = self.rootVC.view;
    root.backgroundColor = [self colorR:0.012 g:0.014 b:0.02 a:1.0];

    UILabel *title = [self labelWithFrame:CGRectMake(20, 50, W - 40, 36)
                                      text:@"Next Mockup Studio"
                                      size:28 bold:YES color:UIColor.whiteColor];
    [root addSubview:title];

    UILabel *sub = [self labelWithFrame:CGRectMake(20, 87, W - 40, 23)
                                    text:@"iPhone 17 Pro Max • Premium test build"
                                    size:14 bold:NO color:[self colorR:0.62 g:0.66 b:0.74 a:1.0]];
    [root addSubview:sub];

    CGFloat canvasY = 124.0;
    CGFloat controlsH = 210.0;
    CGFloat canvasH = H - canvasY - controlsH;
    if (canvasH < 410.0) canvasH = 410.0;
    CGFloat canvasW = W - 32.0;

    self.canvas = [[UIView alloc] initWithFrame:CGRectMake(16, canvasY, canvasW, canvasH)];
    [self setCanvasBackground];
    self.canvas.layer.cornerRadius = 24.0;
    self.canvas.clipsToBounds = YES;
    [root addSubview:self.canvas];

    CGFloat phoneW = canvasW * 0.56;
    phoneW = MIN(250.0, MAX(190.0, phoneW));
    CGFloat phoneH = phoneW * 2.095;
    if (phoneH > canvasH - 34.0) {
        phoneH = canvasH - 34.0;
        phoneW = phoneH / 2.095;
    }
    CGFloat px = (canvasW - phoneW) / 2.0;
    CGFloat py = (canvasH - phoneH) / 2.0;

    self.phone = [[UIView alloc] initWithFrame:CGRectMake(px, py, phoneW, phoneH)];
    self.phone.backgroundColor = UIColor.clearColor;
    [self.canvas addSubview:self.phone];

    CGFloat sx = phoneW * (109.0 / 3000.0);
    CGFloat sy = phoneH * (120.0 / 6285.0);
    CGFloat sw = phoneW * (2782.0 / 3000.0);
    CGFloat sh = phoneH * (6045.0 / 6285.0);

    self.screenshotView = [[UIImageView alloc] initWithFrame:CGRectMake(sx, sy, sw, sh)];
    self.screenshotView.backgroundColor = [self colorR:0.025 g:0.028 b:0.04 a:1.0];
    self.screenshotView.contentMode = UIViewContentModeScaleAspectFill;
    self.screenshotView.clipsToBounds = YES;
    self.screenshotView.layer.cornerRadius = phoneW * (190.0 / 3000.0);
    [self.phone addSubview:self.screenshotView];

    self.hintLabel = [self labelWithFrame:CGRectMake(sx + 10, sy + sh * 0.42, sw - 20, 50)
                                      text:@"IMPORT\nSCREENSHOT"
                                      size:13 bold:YES color:[self colorR:0.70 g:0.74 b:0.82 a:1.0]];
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    self.hintLabel.numberOfLines = 2;
    [self.phone addSubview:self.hintLabel];

    self.frameView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, phoneW, phoneH)];
    self.frameView.contentMode = UIViewContentModeScaleToFill;
    self.frameView.userInteractionEnabled = NO;
    [self updateFrameAsset];
    [self.phone addSubview:self.frameView];

    CGFloat controlsY = canvasY + canvasH + 14.0;
    CGFloat half = (W - 52.0) / 2.0;
    UIButton *importButton = [self buttonWithFrame:CGRectMake(16, controlsY, half, 46)
                                             title:@"Import Screenshot"
                                            action:@selector(pickScreenshot:)];
    [root addSubview:importButton];

    UIButton *saveButton = [self buttonWithFrame:CGRectMake(36 + half, controlsY, half, 46)
                                           title:@"Save PNG"
                                          action:@selector(saveMockup:)];
    [root addSubview:saveButton];

    CGFloat third = (W - 56.0) / 3.0;
    CGFloat y2 = controlsY + 56.0;
    [root addSubview:[self buttonWithFrame:CGRectMake(16, y2, third, 42) title:@"Silver" action:@selector(chooseSilver:)]];
    [root addSubview:[self buttonWithFrame:CGRectMake(20 + third, y2, third, 42) title:@"Orange" action:@selector(chooseOrange:)]];
    [root addSubview:[self buttonWithFrame:CGRectMake(24 + third * 2, y2, third, 42) title:@"Deep Blue" action:@selector(chooseBlue:)]];

    CGFloat y3 = y2 + 51.0;
    [root addSubview:[self buttonWithFrame:CGRectMake(16, y3, 112, 38) title:@"Background" action:@selector(cycleBackground:)]];

    self.scaleSlider = [[UISlider alloc] initWithFrame:CGRectMake(142, y3, W - 158, 38)];
    self.scaleSlider.minimumValue = 0.72f;
    self.scaleSlider.maximumValue = 1.08f;
    self.scaleSlider.value = 0.92f;
    [self.scaleSlider addTarget:self action:@selector(scaleChanged:) forControlEvents:UIControlEventValueChanged];
    [root addSubview:self.scaleSlider];

    self.statusLabel = [self labelWithFrame:CGRectMake(18, y3 + 42, W - 36, 28)
                                       text:@"Ready • iPhone 17 Pro Max • test build"
                                       size:12 bold:NO color:[self colorR:0.55 g:0.60 b:0.70 a:1.0]];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [root addSubview:self.statusLabel];

    self.window.rootViewController = self.rootVC;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)chooseSilver:(id)sender { (void)sender; self.finish = 0; [self updateFrameAsset]; [self setStatus:@"Silver finish selected"]; }
- (void)chooseOrange:(id)sender { (void)sender; self.finish = 1; [self updateFrameAsset]; [self setStatus:@"Cosmic Orange selected"]; }
- (void)chooseBlue:(id)sender { (void)sender; self.finish = 2; [self updateFrameAsset]; [self setStatus:@"Deep Blue selected"]; }

- (void)cycleBackground:(id)sender {
    (void)sender;
    self.backgroundMode = (self.backgroundMode + 1) % 3;
    [self setCanvasBackground];
    [self setStatus:@"Background changed"];
}

- (void)scaleChanged:(UISlider *)sender {
    self.phone.transform = CGAffineTransformMakeScale(sender.value, sender.value);
}

- (void)pickScreenshot:(id)sender {
    (void)sender;
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.allowsEditing = NO;
    [self setStatus:@"Choose a screenshot from Photos"];
    [self.rootVC presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    if (image) {
        self.screenshotView.image = image;
        self.hintLabel.hidden = YES;
        [self setStatus:@"Screenshot fitted to iPhone 17 Pro Max"];
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
    [self setStatus:@"Import cancelled"];
}

- (void)saveMockup:(id)sender {
    (void)sender;
    UIGraphicsBeginImageContextWithOptions(self.canvas.bounds.size, NO, 3.0);
    BOOL ok = [self.canvas drawViewHierarchyInRect:self.canvas.bounds afterScreenUpdates:YES];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (ok && image) {
        UIImageWriteToSavedPhotosAlbum(image, nil, NULL, NULL);
        [self setStatus:@"Saved to Photos ✓"];
    } else {
        [self setStatus:@"Export failed"];
    }
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([NMAppDelegate class]));
    }
}
