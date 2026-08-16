#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <Preferences/PSListController.h>

static NSString * const LGTPrefsDomain = @"com.nextsolution.lockglyphtime";
static CFStringRef const LGTReloadNotification = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");

typedef void (^LGTPhotoCompletion)(UIImage *image);

@interface LGTPhotoCropController : UIViewController <UIScrollViewDelegate>
@property(nonatomic,strong) UIImage *image;
@property(nonatomic,strong) UIScrollView *scrollView;
@property(nonatomic,strong) UIImageView *imageView;
@property(nonatomic,copy) LGTPhotoCompletion completion;
@property(nonatomic,assign) BOOL configured;
- (instancetype)initWithImage:(UIImage *)image completion:(LGTPhotoCompletion)completion;
@end

@implementation LGTPhotoCropController
- (instancetype)initWithImage:(UIImage *)image completion:(LGTPhotoCompletion)completion {
    if ((self=[super init])) { _image=image; _completion=[completion copy]; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Crop Photo"; self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Use Photo" style:UIBarButtonItemStyleDone target:self action:@selector(usePhoto)];
    UILabel *hint=[UILabel new]; hint.translatesAutoresizingMaskIntoConstraints=NO; hint.numberOfLines=0; hint.textAlignment=NSTextAlignmentCenter; hint.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; hint.text=@"Move and zoom the photo inside the square. The saved image is cropped to a square and resized for the icon; Icon Size controls its lock-screen size.";
    [self.view addSubview:hint];
    self.scrollView=[UIScrollView new]; self.scrollView.translatesAutoresizingMaskIntoConstraints=NO; self.scrollView.delegate=self; self.scrollView.clipsToBounds=YES; self.scrollView.backgroundColor=UIColor.blackColor; self.scrollView.layer.borderWidth=2.0; self.scrollView.layer.borderColor=UIColor.separatorColor.CGColor;
    [self.view addSubview:self.scrollView];
    self.imageView=[[UIImageView alloc] initWithImage:self.image]; self.imageView.contentMode=UIViewContentModeScaleAspectFill; [self.scrollView addSubview:self.imageView];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [self.scrollView.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor constant:20],
        [self.scrollView.heightAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
        [hint.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [hint.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [hint.bottomAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:-16]
    ]];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.configured || self.scrollView.bounds.size.width < 10 || !self.image) return;
    CGFloat side=self.scrollView.bounds.size.width;
    CGSize imageSize=self.image.size;
    CGFloat scale=MAX(side/MAX(imageSize.width,1.0), side/MAX(imageSize.height,1.0));
    CGSize display=CGSizeMake(imageSize.width*scale,imageSize.height*scale);
    self.imageView.frame=(CGRect){CGPointZero,display}; self.scrollView.contentSize=display;
    self.scrollView.minimumZoomScale=1.0; self.scrollView.maximumZoomScale=6.0; self.scrollView.zoomScale=1.0;
    self.scrollView.contentOffset=CGPointMake(MAX(0,(display.width-side)/2.0),MAX(0,(display.height-side)/2.0)); self.configured=YES;
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.imageView; }
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (UIImage *)normalizedImage:(UIImage *)image {
    if (image.imageOrientation==UIImageOrientationUp) return image;
    UIGraphicsBeginImageContextWithOptions(image.size,NO,image.scale); [image drawInRect:(CGRect){CGPointZero,image.size}]; UIImage *out=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return out?:image;
}
- (void)usePhoto {
    UIImage *normalized=[self normalizedImage:self.image]; CGFloat zoom=MAX(self.scrollView.zoomScale,0.001);
    CGRect visible=CGRectMake(self.scrollView.contentOffset.x/zoom,self.scrollView.contentOffset.y/zoom,self.scrollView.bounds.size.width/zoom,self.scrollView.bounds.size.height/zoom);
    CGFloat sx=normalized.size.width/MAX(self.imageView.bounds.size.width,1.0), sy=normalized.size.height/MAX(self.imageView.bounds.size.height,1.0);
    CGRect crop=CGRectMake(visible.origin.x*sx,visible.origin.y*sy,visible.size.width*sx,visible.size.height*sy);
    crop=CGRectIntersection(crop,(CGRect){CGPointZero,normalized.size});
    CGImageRef cg=normalized.CGImage; if (!cg || CGRectIsEmpty(crop)) return;
    CGFloat px=(CGFloat)CGImageGetWidth(cg)/MAX(normalized.size.width,1.0), py=(CGFloat)CGImageGetHeight(cg)/MAX(normalized.size.height,1.0);
    CGRect pixelRect=CGRectMake(crop.origin.x*px,crop.origin.y*py,crop.size.width*px,crop.size.height*py);
    CGImageRef cropped=CGImageCreateWithImageInRect(cg,pixelRect); if(!cropped)return;
    UIImage *piece=[UIImage imageWithCGImage:cropped scale:1 orientation:UIImageOrientationUp]; CGImageRelease(cropped);
    CGSize target=CGSizeMake(512,512); UIGraphicsBeginImageContextWithOptions(target,YES,1.0); [piece drawInRect:(CGRect){CGPointZero,target}]; UIImage *final=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    LGTPhotoCompletion completion=self.completion; [self dismissViewControllerAnimated:YES completion:^{ if(completion&&final)completion(final); }];
}
@end

@interface LGTListController : PSListController <UIColorPickerViewControllerDelegate,PHPickerViewControllerDelegate>
@property(nonatomic,copy) NSString *activeColorKey;
@end

@implementation LGTListController
- (NSArray *)specifiers { if(!_specifiers)_specifiers=[self loadSpecifiersFromPlistName:@"Root" target:self]; return _specifiers; }
- (UIColor *)lgt_colorFromHex:(NSString *)hex fallback:(UIColor *)fallback {
    NSString *clean=[[hex?:@"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString]; if([clean hasPrefix:@"#"])clean=[clean substringFromIndex:1]; if(clean.length!=6&&clean.length!=8)return fallback;
    unsigned long long value=0;NSScanner *scanner=[NSScanner scannerWithString:clean];if(![scanner scanHexLongLong:&value]||!scanner.isAtEnd)return fallback;CGFloat r,g,b,a=1;
    if(clean.length==8){r=((value>>24)&255)/255.0;g=((value>>16)&255)/255.0;b=((value>>8)&255)/255.0;a=(value&255)/255.0;}else{r=((value>>16)&255)/255.0;g=((value>>8)&255)/255.0;b=(value&255)/255.0;}return[UIColor colorWithRed:r green:g blue:b alpha:a];
}
- (NSString *)lgt_hexFromColor:(UIColor *)color { CGFloat r=0,g=0,b=0,a=1;if(![color getRed:&r green:&g blue:&b alpha:&a]){CGFloat w=1;[color getWhite:&w alpha:&a];r=g=b=w;}return[NSString stringWithFormat:@"#%02X%02X%02X%02X",(int)lrint(r*255),(int)lrint(g*255),(int)lrint(b*255),(int)lrint(a*255)]; }
- (void)lgt_presentColorPickerForKey:(NSString *)key defaultHex:(NSString *)defaultHex title:(NSString *)title { self.activeColorKey=key;NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];UIColorPickerViewController *picker=[UIColorPickerViewController new];picker.delegate=self;picker.supportsAlpha=YES;picker.title=title;picker.selectedColor=[self lgt_colorFromHex:[prefs stringForKey:key]?:defaultHex fallback:UIColor.whiteColor];[self presentViewController:picker animated:YES completion:nil]; }
- (void)lgt_saveSelectedColor:(UIColor *)color { if(!self.activeColorKey.length||!color)return;NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];[prefs setObject:[self lgt_hexFromColor:color] forKey:self.activeColorKey];[prefs synchronize];CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),LGTReloadNotification,NULL,NULL,true); }
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)){[self lgt_saveSelectedColor:viewController.selectedColor];}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)){[self lgt_saveSelectedColor:viewController.selectedColor];self.activeColorKey=nil;}
- (void)openTimeColorPicker{[self lgt_presentColorPickerForKey:@"timeColor" defaultHex:@"#FFFFFFFF" title:@"Time Color"];}
- (void)openTimeShadowColorPicker{[self lgt_presentColorPickerForKey:@"timeShadowColor" defaultHex:@"#000000FF" title:@"Time Shadow Color"];}
- (void)openDateColorPicker{[self lgt_presentColorPickerForKey:@"dateColor" defaultHex:@"#FFFFFFFF" title:@"Date Color"];}
- (void)openDateShadowColorPicker{[self lgt_presentColorPickerForKey:@"dateShadowColor" defaultHex:@"#000000FF" title:@"Date Shadow Color"];}
- (void)openIconColorPicker{[self lgt_presentColorPickerForKey:@"iconColor" defaultHex:@"#FFFFFFFF" title:@"Icon Color"];}
- (void)openIconShadowColorPicker{[self lgt_presentColorPickerForKey:@"shadowColor" defaultHex:@"#000000FF" title:@"Icon Shadow Color"];}

- (void)openCustomPhotoPicker {
    PHPickerConfiguration *config=[[PHPickerConfiguration alloc] init]; config.selectionLimit=1; config.filter=[PHPickerFilter imagesFilter];
    PHPickerViewController *picker=[[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate=self; [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil]; PHPickerResult *result=results.firstObject; if(!result)return; NSItemProvider *provider=result.itemProvider; if(![provider canLoadObjectOfClass:UIImage.class])return;
    __weak typeof(self) weakSelf=self; [provider loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object,NSError *error){ if(error||![object isKindOfClass:UIImage.class])return; dispatch_async(dispatch_get_main_queue(),^{ typeof(self) selfRef=weakSelf; if(!selfRef)return; LGTPhotoCropController *editor=[[LGTPhotoCropController alloc] initWithImage:(UIImage *)object completion:^(UIImage *image){ NSData *data=UIImageJPEGRepresentation(image,.92); if(!data)return; NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain]; [prefs setObject:data forKey:@"customPhotoData"]; [prefs setObject:@"custom.photo" forKey:@"iconName"]; [prefs synchronize]; CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),LGTReloadNotification,NULL,NULL,true); [selfRef reloadSpecifiers]; }]; UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:editor]; [selfRef presentViewController:nav animated:YES completion:nil]; }); }];
}
- (void)removeCustomPhoto { NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];[prefs removeObjectForKey:@"customPhotoData"];if([[prefs stringForKey:@"iconName"] isEqualToString:@"custom.photo"])[prefs setObject:@"photo.fill" forKey:@"iconName"];[prefs synchronize];CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),LGTReloadNotification,NULL,NULL,true);[self reloadSpecifiers]; }
@end
