#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parent
runtime_src = (ROOT / "RuntimeV022.xm").read_text()
prefs_src = (ROOT / "prefs" / "LGTListController.m").read_text()

runtime_insert_anchor = '''@implementation LGTLabelState\n@end\n'''
runtime_insert = r'''

@interface LGTIconHostView : UIView
@property(nonatomic,strong) UIImageView *imageView;
@end
@implementation LGTIconHostView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;
        self.userInteractionEnabled=NO;
        self.clipsToBounds=NO;
        _imageView=[[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        _imageView.backgroundColor=UIColor.clearColor;
        _imageView.userInteractionEnabled=NO;
        [self addSubview:_imageView];
    }
    return self;
}
@end

static BOOL LGTImageHasVisibleTransparency(UIImage *image) {
    CGImageRef cg=image.CGImage;
    if(!cg)return NO;
    CGImageAlphaInfo alphaInfo=CGImageGetAlphaInfo(cg);
    BOOL alphaCapable=(alphaInfo==kCGImageAlphaPremultipliedLast||alphaInfo==kCGImageAlphaPremultipliedFirst||alphaInfo==kCGImageAlphaLast||alphaInfo==kCGImageAlphaFirst);
    if(!alphaCapable)return NO;
    size_t width=MIN((size_t)32,MAX((size_t)1,CGImageGetWidth(cg)));
    size_t height=MIN((size_t)32,MAX((size_t)1,CGImageGetHeight(cg)));
    size_t bytesPerRow=width*4;
    unsigned char *pixels=(unsigned char *)calloc(height,bytesPerRow);
    if(!pixels)return NO;
    CGColorSpaceRef colorSpace=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,width,height,8,bytesPerRow,colorSpace,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if(!context){free(pixels);return NO;}
    CGContextClearRect(context,CGRectMake(0,0,width,height));
    CGContextSetInterpolationQuality(context,kCGInterpolationLow);
    CGContextDrawImage(context,CGRectMake(0,0,width,height),cg);
    BOOL transparent=NO;
    for(size_t i=0;i<width*height;i++){
        if(pixels[i*4+3] < 250){transparent=YES;break;}
    }
    CGContextRelease(context); free(pixels); return transparent;
}
'''
if runtime_insert_anchor not in runtime_src: raise SystemExit("Runtime class anchor not found")
runtime_src = runtime_src.replace(runtime_insert_anchor, runtime_insert_anchor + runtime_insert, 1)

old_apply = r'''static void LGTApplyIcon(UIView *container,UILabel *time,UILabel *date) {
    UIImageView *icon=objc_getAssociatedObject(container,LGTIconAssociationKey);
    if(!gEnabled||!gIconEnabled||!time){[icon removeFromSuperview];objc_setAssociatedObject(container,LGTIconAssociationKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);return;}
    if(!icon){icon=[[UIImageView alloc] initWithFrame:CGRectZero];icon.userInteractionEnabled=NO;[container addSubview:icon];objc_setAssociatedObject(container,LGTIconAssociationKey,icon,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    BOOL custom=[gIconName isEqualToString:@"custom.photo"]&&gCustomPhotoImage;
    icon.image=LGTIconImage(); icon.contentMode=custom?UIViewContentModeScaleAspectFill:UIViewContentModeScaleAspectFit; icon.tintColor=custom?nil:(gIconUIColor?:UIColor.whiteColor);
    icon.layer.shadowOpacity=gShadowEnabled?(float)gShadowOpacity:0;icon.layer.shadowRadius=gShadowRadius;icon.layer.shadowOffset=CGSizeMake(gShadowOffsetX,gShadowOffsetY);icon.layer.shadowColor=(gIconShadowUIColor?:UIColor.blackColor).CGColor;icon.layer.masksToBounds=NO;
    UILabel *anchor=(gAnchorTarget==1&&date)?date:time; CGRect frame=[anchor convertRect:anchor.bounds toView:container]; icon.frame=LGTIconFrame(frame,gIconSize,gIconPosition); [container bringSubviewToFront:icon];
}
'''
new_apply = r'''static void LGTApplyIcon(UIView *container,UILabel *time,UILabel *date) {
    LGTIconHostView *host=objc_getAssociatedObject(container,LGTIconAssociationKey);
    if(!gEnabled||!gIconEnabled||!time){[host removeFromSuperview];objc_setAssociatedObject(container,LGTIconAssociationKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);return;}
    if(!host){host=[[LGTIconHostView alloc] initWithFrame:CGRectZero];[container addSubview:host];objc_setAssociatedObject(container,LGTIconAssociationKey,host,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    UIImageView *icon=host.imageView;
    BOOL custom=[gIconName isEqualToString:@"custom.photo"]&&gCustomPhotoImage;
    BOOL sticker=custom&&LGTImageHasVisibleTransparency(gCustomPhotoImage);
    icon.image=LGTIconImage(); icon.tintColor=custom?nil:(gIconUIColor?:UIColor.whiteColor); icon.layer.mask=nil; icon.layer.cornerRadius=0; icon.clipsToBounds=NO;
    if(custom){ if(sticker){ icon.contentMode=UIViewContentModeScaleAspectFit; } else { icon.contentMode=UIViewContentModeScaleAspectFill; icon.layer.cornerRadius=MAX(4.0,gIconSize*0.22); icon.clipsToBounds=YES; } }
    else icon.contentMode=UIViewContentModeScaleAspectFit;
    host.layer.shadowOpacity=gShadowEnabled?(float)gShadowOpacity:0; host.layer.shadowRadius=gShadowRadius; host.layer.shadowOffset=CGSizeMake(gShadowOffsetX,gShadowOffsetY); host.layer.shadowColor=(gIconShadowUIColor?:UIColor.blackColor).CGColor; host.layer.masksToBounds=NO; host.layer.shadowPath=nil;
    UILabel *anchor=(gAnchorTarget==1&&date)?date:time; CGRect frame=[anchor convertRect:anchor.bounds toView:container]; host.frame=LGTIconFrame(frame,gIconSize,gIconPosition); icon.frame=host.bounds; [container bringSubviewToFront:host];
}
'''
if old_apply not in runtime_src: raise SystemExit("Original LGTApplyIcon block not found")
runtime_src = runtime_src.replace(old_apply,new_apply,1)
(ROOT/"RuntimeV023.xm").write_text(runtime_src)

old_canvas='CGSize target=CGSizeMake(512,512); UIGraphicsBeginImageContextWithOptions(target,YES,1.0); [piece drawInRect:(CGRect){CGPointZero,target}]; UIImage *final=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();'
new_canvas='CGSize target=CGSizeMake(512,512); UIGraphicsBeginImageContextWithOptions(target,NO,1.0); [[UIColor clearColor] setFill]; UIRectFill((CGRect){CGPointZero,target}); [piece drawInRect:(CGRect){CGPointZero,target} blendMode:kCGBlendModeNormal alpha:1.0]; UIImage *final=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();'
if old_canvas not in prefs_src: raise SystemExit("Photo crop canvas block not found")
prefs_src=prefs_src.replace(old_canvas,new_canvas,1)
old_save='LGTPhotoCropController *editor=[[LGTPhotoCropController alloc] initWithImage:(UIImage *)object completion:^(UIImage *image){ NSData *data=UIImageJPEGRepresentation(image,.92); if(!data)return; NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain]; [prefs setObject:data forKey:@"customPhotoData"]; [prefs setObject:@"custom.photo" forKey:@"iconName"]; [prefs synchronize]; CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),LGTReloadNotification,NULL,NULL,true); [selfRef reloadSpecifiers]; }];'
new_save='LGTPhotoCropController *editor=[[LGTPhotoCropController alloc] initWithImage:(UIImage *)object completion:^(UIImage *image){ NSData *data=UIImagePNGRepresentation(image); if(!data)return; NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain]; [prefs setObject:data forKey:@"customPhotoData"]; [prefs setObject:@"custom.photo" forKey:@"iconName"]; [prefs synchronize]; CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),LGTReloadNotification,NULL,NULL,true); [selfRef reloadSpecifiers]; }];'
if old_save not in prefs_src: raise SystemExit("Photo save block not found")
prefs_src=prefs_src.replace(old_save,new_save,1)
old_hint='@"Move and zoom the photo inside the square. The saved image is cropped to a square and resized for the icon; Icon Size controls its lock-screen size."'
new_hint='@"Move and zoom the photo inside the square. Transparent PNG/sticker backgrounds are preserved; normal photos are shown as rounded squares. Icon Size controls the lock-screen size."'
if old_hint not in prefs_src: raise SystemExit("Photo hint string not found")
prefs_src=prefs_src.replace(old_hint,new_hint,1)

old_spec='- (NSArray *)specifiers { if(!_specifiers)_specifiers=[self loadSpecifiersFromPlistName:@"Root" target:self]; return _specifiers; }'
new_spec='- (NSString *)lgt_plistName { return @"Root"; }\n- (NSArray *)specifiers { if(!_specifiers)_specifiers=[self loadSpecifiersFromPlistName:[self lgt_plistName] target:self]; return _specifiers; }'
if old_spec not in prefs_src: raise SystemExit("Specifier method not found")
prefs_src=prefs_src.replace(old_spec,new_spec,1)

final_end=prefs_src.rfind('\n@end')
if final_end<0: raise SystemExit("Controller end not found")
extra=r'''

- (void)viewDidLoad {
    [super viewDidLoad];
    if(![[self lgt_plistName] isEqualToString:@"Root"]) return;
    self.title=@"NextStyle";
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,320,142)];
    UIImage *logo=[UIImage imageNamed:@"NextStyleIcon" inBundle:[NSBundle bundleForClass:self.class] compatibleWithTraitCollection:nil];
    UIImageView *iv=[[UIImageView alloc] initWithImage:logo]; iv.frame=CGRectMake(24,24,72,72); iv.layer.cornerRadius=16; iv.clipsToBounds=YES; iv.contentMode=UIViewContentModeScaleAspectFit; [header addSubview:iv];
    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(112,28,190,34)]; title.text=@"NextStyle"; title.font=[UIFont systemFontOfSize:28 weight:UIFontWeightBold]; [header addSubview:title];
    UILabel *sub=[[UILabel alloc] initWithFrame:CGRectMake(112,60,190,24)]; sub.text=@"for Lock Screen"; sub.font=[UIFont systemFontOfSize:16 weight:UIFontWeightMedium]; sub.textColor=UIColor.secondaryLabelColor; [header addSubview:sub];
    UILabel *brand=[[UILabel alloc] initWithFrame:CGRectMake(112,84,190,20)]; brand.text=@"by Next Solution"; brand.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]; brand.textColor=[UIColor colorWithRed:0.48 green:0.34 blue:1 alpha:1]; [header addSubview:brand];
    UILabel *tag=[[UILabel alloc] initWithFrame:CGRectMake(24,110,278,24)]; tag.text=@"Lock Screen, your way."; tag.textAlignment=NSTextAlignmentCenter; tag.font=[UIFont systemFontOfSize:14 weight:UIFontWeightMedium]; tag.textColor=UIColor.secondaryLabelColor; [header addSubview:tag];
    UITableView *table=nil; @try { table=(UITableView *)[self valueForKey:@"table"]; } @catch(NSException *e) {} if([table isKindOfClass:UITableView.class]) table.tableHeaderView=header;
}
- (void)lgtNotify { CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),LGTReloadNotification,NULL,NULL,true); }
- (void)applyNow { [self lgtNotify]; UIAlertController *a=[UIAlertController alertControllerWithTitle:@"NextStyle" message:@"Changes applied." preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)resetKeys:(NSArray<NSString *> *)keys { NSUserDefaults *p=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain]; for(NSString *k in keys)[p removeObjectForKey:k]; [p synchronize]; [self lgtNotify]; [self reloadSpecifiers]; }
- (void)resetTime { [self resetKeys:@[@"customTimeEnabled",@"timeScale",@"timeColor",@"timeOffsetX",@"timeOffsetY",@"timeAlignment",@"timeFont",@"timeFontWeight",@"timeStyle",@"timeShadowEnabled",@"timeShadowColor",@"timeShadowOpacity",@"timeShadowRadius",@"timeShadowOffsetX",@"timeShadowOffsetY"]]; }
- (void)resetDate { [self resetKeys:@[@"customDateEnabled",@"dateScale",@"dateColor",@"dateOffsetX",@"dateOffsetY",@"dateAlignment",@"dateFont",@"dateFontWeight",@"dateStyle",@"dateFormat",@"customDateFormat",@"dateShadowEnabled",@"dateShadowColor",@"dateShadowOpacity",@"dateShadowRadius",@"dateShadowOffsetX",@"dateShadowOffsetY"]]; }
- (void)resetIcon { [self resetKeys:@[@"iconEnabled",@"iconName",@"iconSize",@"iconColor",@"anchorTarget",@"iconPosition",@"iconOffsetX",@"iconOffsetY",@"shadowEnabled",@"shadowColor",@"shadowOpacity",@"shadowRadius",@"shadowOffsetX",@"shadowOffsetY",@"customPhotoData"]]; }
- (void)resetAll { [[NSUserDefaults standardUserDefaults] synchronize]; NSUserDefaults *p=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain]; [p removePersistentDomainForName:LGTPrefsDomain]; [p synchronize]; [self lgtNotify]; [self reloadSpecifiers]; }
- (void)openWebsite { NSURL *u=[NSURL URLWithString:@"https://nextsolution.cc"]; if(u)[UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil]; }
- (void)openYouTube { NSURL *u=[NSURL URLWithString:@"https://www.youtube.com/@zeshan0727"]; if(u)[UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil]; }
'''
prefs_src=prefs_src[:final_end]+extra+prefs_src[final_end:]

subclasses=r'''

@interface LGTTimeController : LGTListController @end
@implementation LGTTimeController
- (NSString *)lgt_plistName { return @"Time"; }
@end
@interface LGTDateController : LGTListController @end
@implementation LGTDateController
- (NSString *)lgt_plistName { return @"Date"; }
@end
@interface LGTIconController : LGTListController @end
@implementation LGTIconController
- (NSString *)lgt_plistName { return @"Icon"; }
@end
@interface LGTPhotoController : LGTListController @end
@implementation LGTPhotoController
- (NSString *)lgt_plistName { return @"Photo"; }
@end
@interface LGTAdvancedController : LGTListController @end
@implementation LGTAdvancedController
- (NSString *)lgt_plistName { return @"Advanced"; }
@end
@interface LGTAboutController : LGTListController @end
@implementation LGTAboutController
- (NSString *)lgt_plistName { return @"About"; }
@end
'''
prefs_src+=subclasses
(ROOT/"prefs"/"LGTListControllerV023.m").write_text(prefs_src)
print("Generated RuntimeV023.xm and branded NextStyle preference controller")
