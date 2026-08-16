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
    unsigned char *pixels=calloc(height,bytesPerRow);
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
    CGContextRelease(context);
    free(pixels);
    return transparent;
}
'''
if runtime_insert_anchor not in runtime_src:
    raise SystemExit("Runtime class anchor not found")
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
    icon.image=LGTIconImage();
    icon.tintColor=custom?nil:(gIconUIColor?:UIColor.whiteColor);
    icon.layer.mask=nil;
    icon.layer.cornerRadius=0;
    icon.clipsToBounds=NO;
    if(custom){
        if(sticker){
            icon.contentMode=UIViewContentModeScaleAspectFit;
        }else{
            icon.contentMode=UIViewContentModeScaleAspectFill;
            icon.layer.cornerRadius=MAX(4.0,gIconSize*0.22);
            icon.clipsToBounds=YES;
        }
    }else{
        icon.contentMode=UIViewContentModeScaleAspectFit;
    }
    host.layer.shadowOpacity=gShadowEnabled?(float)gShadowOpacity:0;
    host.layer.shadowRadius=gShadowRadius;
    host.layer.shadowOffset=CGSizeMake(gShadowOffsetX,gShadowOffsetY);
    host.layer.shadowColor=(gIconShadowUIColor?:UIColor.blackColor).CGColor;
    host.layer.masksToBounds=NO;
    host.layer.shadowPath=nil;
    UILabel *anchor=(gAnchorTarget==1&&date)?date:time;
    CGRect frame=[anchor convertRect:anchor.bounds toView:container];
    host.frame=LGTIconFrame(frame,gIconSize,gIconPosition);
    icon.frame=host.bounds;
    [container bringSubviewToFront:host];
}
'''
if old_apply not in runtime_src:
    raise SystemExit("Original LGTApplyIcon block not found")
runtime_src = runtime_src.replace(old_apply, new_apply, 1)
(ROOT / "RuntimeV023.xm").write_text(runtime_src)

old_canvas = 'CGSize target=CGSizeMake(512,512); UIGraphicsBeginImageContextWithOptions(target,YES,1.0); [piece drawInRect:(CGRect){CGPointZero,target}]; UIImage *final=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();'
new_canvas = 'CGSize target=CGSizeMake(512,512); UIGraphicsBeginImageContextWithOptions(target,NO,1.0); [[UIColor clearColor] setFill]; UIRectFill((CGRect){CGPointZero,target}); [piece drawInRect:(CGRect){CGPointZero,target} blendMode:kCGBlendModeNormal alpha:1.0]; UIImage *final=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();'
if old_canvas not in prefs_src:
    raise SystemExit("Photo crop canvas block not found")
prefs_src = prefs_src.replace(old_canvas, new_canvas, 1)

old_save = 'LGTPhotoCropController *editor=[[LGTPhotoCropController alloc] initWithImage:(UIImage *)object completion:^(UIImage *image){ NSData *data=UIImageJPEGRepresentation(image,.92); if(!data)return; NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain]; [prefs setObject:data forKey:@"customPhotoData"]; [prefs setObject:@"custom.photo" forKey:@"iconName"]; [prefs synchronize]; CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),LGTReloadNotification,NULL,NULL,true); [selfRef reloadSpecifiers]; }];'
new_save = 'LGTPhotoCropController *editor=[[LGTPhotoCropController alloc] initWithImage:(UIImage *)object completion:^(UIImage *image){ NSData *data=UIImagePNGRepresentation(image); if(!data)return; NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain]; [prefs setObject:data forKey:@"customPhotoData"]; [prefs setObject:@"custom.photo" forKey:@"iconName"]; [prefs synchronize]; CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),LGTReloadNotification,NULL,NULL,true); [selfRef reloadSpecifiers]; }];'
if old_save not in prefs_src:
    raise SystemExit("Photo save block not found")
prefs_src = prefs_src.replace(old_save, new_save, 1)

old_hint = '@"Move and zoom the photo inside the square. The saved image is cropped to a square and resized for the icon; Icon Size controls its lock-screen size."'
new_hint = '@"Move and zoom the photo inside the square. Transparent PNG/sticker backgrounds are preserved; normal photos are shown as rounded squares. Icon Size controls the lock-screen size."'
if old_hint not in prefs_src:
    raise SystemExit("Photo hint string not found")
prefs_src = prefs_src.replace(old_hint, new_hint, 1)
(ROOT / "prefs" / "LGTListControllerV023.m").write_text(prefs_src)

print("Generated RuntimeV023.xm and prefs/LGTListControllerV023.m")
