#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString *const NLDomain=@"com.nextsolution.lockglyphtime";
static CFStringRef const NLChanged=CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");

static void NLNotify(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NLDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),NLChanged,NULL,NULL,YES);
}

static NSString *NLFrameKey(NSInteger frame, NSString *suffix) {
    if (frame==1 && [suffix isEqualToString:@"Width"]) return @"photoFrameWidth";
    if (frame==1 && [suffix isEqualToString:@"Height"]) return @"photoFrameHeight";
    return [NSString stringWithFormat:@"photoFrame%ld%@",(long)frame,suffix];
}

static PSSpecifier *NLGroup(NSString *title, NSString *footer) {
    PSSpecifier *s=[PSSpecifier groupSpecifierWithName:title];
    if (footer.length) [s setProperty:footer forKey:@"footerText"];
    return s;
}

@interface NLPhotoRootController : PSListController
@end

@interface NLPhotoFrameController : PSListController <UIImagePickerControllerDelegate,UINavigationControllerDelegate>
@property(nonatomic) NSInteger frameIndex;
@end

@interface NLPhotoFrame1Controller : NLPhotoFrameController @end
@interface NLPhotoFrame2Controller : NLPhotoFrameController @end
@interface NLPhotoFrame3Controller : NLPhotoFrameController @end
@interface NLPhotoFrame4Controller : NLPhotoFrameController @end

@implementation NLPhotoRootController
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *a=[NSMutableArray array];
    [a addObject:NLGroup(@"PHOTO-ONLY RECOVERY",@"Clean Test 20.2 contains only the four-photo renderer and these photo controls. It has no activation system and starts active by default.")];
    PSSpecifier *enabled=[PSSpecifier preferenceSpecifierNamed:@"Enable Photo Frames" target:self set:@selector(setValue:specifier:) get:@selector(readValue:) detail:nil cell:PSSwitchCell edit:nil];
    [enabled setProperty:@"enabled" forKey:@"key"]; [enabled setProperty:@YES forKey:@"default"]; [a addObject:enabled];
    [a addObject:NLGroup(@"PHOTO FRAMES",@"Each photo or transparent sticker has independent selection, size, anchor, placement and X/Y position.")];
    NSArray *classes=@[NLPhotoFrame1Controller.class,NLPhotoFrame2Controller.class,NLPhotoFrame3Controller.class,NLPhotoFrame4Controller.class];
    for (NSInteger i=0;i<4;i++) [a addObject:[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"Frame %ld",(long)i+1] target:self set:nil get:nil detail:classes[i] cell:PSLinkCell edit:nil]];
    [a addObject:NLGroup(@"",@"NextLock Test 20.2 Photo Only • Active by default")];
    _specifiers=[a copy]; return _specifiers;
}
- (id)readValue:(PSSpecifier *)s { return (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)[s propertyForKey:@"key"],(__bridge CFStringRef)NLDomain) ?: [s propertyForKey:@"default"]; }
- (void)setValue:(id)value specifier:(PSSpecifier *)s { CFPreferencesSetAppValue((__bridge CFStringRef)[s propertyForKey:@"key"],(__bridge CFTypeRef)value,(__bridge CFStringRef)NLDomain); NLNotify(); }
@end

@implementation NLPhotoFrameController
- (instancetype)init { if ((self=[super init])) _frameIndex=1; return self; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSInteger i=self.frameIndex; NSMutableArray *a=[NSMutableArray array];
    [a addObject:NLGroup([NSString stringWithFormat:@"FRAME %ld",(long)i],@"Choosing or editing a photo enables this frame automatically. Transparent PNGs remain sticker-style.")];
    PSSpecifier *on=[PSSpecifier preferenceSpecifierNamed:@"Enable Frame" target:self set:@selector(setValue:specifier:) get:@selector(readValue:) detail:nil cell:PSSwitchCell edit:nil];
    [on setProperty:NLFrameKey(i,@"Enabled") forKey:@"key"]; [on setProperty:@NO forKey:@"default"]; [a addObject:on];
    PSSpecifier *choose=[PSSpecifier preferenceSpecifierNamed:@"Choose / Edit Photo" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; choose->action=@selector(choosePhoto); [a addObject:choose];
    PSSpecifier *remove=[PSSpecifier preferenceSpecifierNamed:@"Remove Photo" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; remove->action=@selector(removePhoto); [a addObject:remove];
    [a addObject:NLGroup(@"PHOTO DISPLAY",@"Auto preserves transparent stickers and crops opaque photos. Stretch fills the frame, Full Photo shows the entire image, and Cut / Crop fills and crops.")];
    [a addObject:[self list:@"Photo Display" key:NLFrameKey(i,@"ContentMode") titles:@[@"Auto (Recommended)",@"Stretch",@"Full Photo",@"Cut / Crop"] values:@[@0,@1,@2,@3] fallback:@0]];
    [a addObject:NLGroup(@"SIZE",@"Width and height are independent.")];
    [a addObject:[self slider:@"Width" key:NLFrameKey(i,@"Width") min:20 max:600 fallback:90]];
    [a addObject:[self slider:@"Height" key:NLFrameKey(i,@"Height") min:20 max:600 fallback:90]];
    [a addObject:NLGroup(@"POSITION",@"Anchor to the native Lock Screen time or date, select a side, then fine-tune X and Y.")];
    [a addObject:[self list:@"Anchor To" key:NLFrameKey(i,@"AnchorTarget") titles:@[@"Time",@"Date"] values:@[@0,@1] fallback:@0]];
    [a addObject:[self list:@"Placement" key:NLFrameKey(i,@"Position") titles:@[@"Left",@"Right",@"Above",@"Below"] values:@[@0,@1,@2,@3] fallback:@1]];
    [a addObject:[self slider:@"Horizontal Offset" key:NLFrameKey(i,@"OffsetX") min:-500 max:500 fallback:0]];
    [a addObject:[self slider:@"Vertical Offset" key:NLFrameKey(i,@"OffsetY") min:-500 max:500 fallback:0]];
    _specifiers=[a copy]; return _specifiers;
}
- (PSSpecifier *)slider:(NSString *)name key:(NSString *)key min:(double)min max:(double)max fallback:(double)fallback {
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setValue:specifier:) get:@selector(readValue:) detail:nil cell:PSSliderCell edit:nil];
    [s setProperty:key forKey:@"key"]; [s setProperty:@(fallback) forKey:@"default"]; [s setProperty:@(min) forKey:@"min"]; [s setProperty:@(max) forKey:@"max"]; [s setProperty:@YES forKey:@"showValue"]; return s;
}
- (PSSpecifier *)list:(NSString *)name key:(NSString *)key titles:(NSArray *)titles values:(NSArray *)values fallback:(id)fallback {
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setValue:specifier:) get:@selector(readValue:) detail:NSClassFromString(@"PSListItemsController") cell:PSLinkListCell edit:nil];
    [s setProperty:key forKey:@"key"]; [s setProperty:fallback forKey:@"default"]; [s setProperty:titles forKey:@"validTitles"]; [s setProperty:values forKey:@"validValues"]; return s;
}
- (id)readValue:(PSSpecifier *)s { id v=(__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)[s propertyForKey:@"key"],(__bridge CFStringRef)NLDomain); return v ?: [s propertyForKey:@"default"]; }
- (void)setValue:(id)value specifier:(PSSpecifier *)s { CFPreferencesSetAppValue((__bridge CFStringRef)[s propertyForKey:@"key"],(__bridge CFTypeRef)value,(__bridge CFStringRef)NLDomain); NLNotify(); }
- (void)choosePhoto { UIImagePickerController *p=[UIImagePickerController new]; p.sourceType=UIImagePickerControllerSourceTypePhotoLibrary; p.allowsEditing=YES; p.delegate=self; [self presentViewController:p animated:YES completion:nil]; }
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image=info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    NSString *dir=@"/var/mobile/Library/NextLockPhotos"; [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [UIImagePNGRepresentation(image) writeToFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"frame%ld.png",(long)self.frameIndex]] atomically:YES];
    CFPreferencesSetAppValue((__bridge CFStringRef)NLFrameKey(self.frameIndex,@"Enabled"),kCFBooleanTrue,(__bridge CFStringRef)NLDomain); NLNotify();
    [picker dismissViewControllerAnimated:YES completion:^{ [self reloadSpecifiers]; }];
}
- (void)removePhoto { [[NSFileManager defaultManager] removeItemAtPath:[@"/var/mobile/Library/NextLockPhotos" stringByAppendingPathComponent:[NSString stringWithFormat:@"frame%ld.png",(long)self.frameIndex]] error:nil]; CFPreferencesSetAppValue((__bridge CFStringRef)NLFrameKey(self.frameIndex,@"Enabled"),kCFBooleanFalse,(__bridge CFStringRef)NLDomain); NLNotify(); }
@end

@implementation NLPhotoFrame1Controller - (instancetype)init { if((self=[super init])) self.frameIndex=1; return self; } @end
@implementation NLPhotoFrame2Controller - (instancetype)init { if((self=[super init])) self.frameIndex=2; return self; } @end
@implementation NLPhotoFrame3Controller - (instancetype)init { if((self=[super init])) self.frameIndex=3; return self; } @end
@implementation NLPhotoFrame4Controller - (instancetype)init { if((self=[super init])) self.frameIndex=4; return self; } @end
