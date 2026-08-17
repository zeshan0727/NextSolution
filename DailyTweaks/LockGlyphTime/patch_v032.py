#!/usr/bin/env python3
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parent
runtime_path = ROOT / 'RuntimeV023.xm'
prefs_path = ROOT / 'prefs' / 'LGTListControllerV023.m'
runtime = runtime_path.read_text()
prefs = prefs_path.read_text()

# ---------------------------------------------------------------------------
# Runtime: four simultaneous custom-photo/sticker frames.
# Frame 1 migrates the existing customPhotoData + photoFrameWidth/Height.
# Frames 2-4 use their own data, size, anchor, placement and X/Y offsets.
# ---------------------------------------------------------------------------
assoc_anchor = 'static const void *LGTIconAssociationKey = &LGTIconAssociationKey;'
if assoc_anchor not in runtime:
    raise SystemExit('icon association anchor not found')
runtime = runtime.replace(assoc_anchor, assoc_anchor + '\nstatic char LGTPhotoFrameAssociationKeys[4];', 1)

global_anchor = 'static UIImage *gCustomPhotoImage = nil;'
slot_globals = r'''

static BOOL gPhotoSlotEnabled[4] = {NO,NO,NO,NO};
static CGFloat gPhotoSlotWidth[4] = {22.0,22.0,22.0,22.0};
static CGFloat gPhotoSlotHeight[4] = {22.0,22.0,22.0,22.0};
static NSInteger gPhotoSlotAnchor[4] = {0,0,0,0};
static NSInteger gPhotoSlotPosition[4] = {1,1,1,1};
static CGFloat gPhotoSlotOffsetX[4] = {0.0,0.0,0.0,0.0};
static CGFloat gPhotoSlotOffsetY[4] = {0.0,0.0,0.0,0.0};
static NSData *gPhotoSlotData[4] = {nil,nil,nil,nil};
static UIImage *gPhotoSlotImage[4] = {nil,nil,nil,nil};
'''
if global_anchor not in runtime:
    raise SystemExit('custom photo globals anchor not found')
runtime = runtime.replace(global_anchor, global_anchor + slot_globals, 1)

position_load = '    gAnchorTarget=I(@"anchorTarget",0); gIconPosition=I(@"iconPosition",1); gIconOffsetX=D(@"iconOffsetX",0.0,-120.0,120.0); gIconOffsetY=D(@"iconOffsetY",0.0,-120.0,120.0);'
slot_load = r'''

    // Frame 1 keeps the legacy width/height. Position defaults migrate from the
    // previous single custom-photo/icon positioning values.
    gPhotoSlotEnabled[0]=B(@"photoFrame1Enabled",NO);
    gPhotoSlotWidth[0]=gPhotoFrameWidth;
    gPhotoSlotHeight[0]=gPhotoFrameHeight;
    gPhotoSlotAnchor[0]=I(@"photoFrame1AnchorTarget",gAnchorTarget);
    gPhotoSlotPosition[0]=I(@"photoFrame1Position",gIconPosition);
    gPhotoSlotOffsetX[0]=D(@"photoFrame1OffsetX",gIconOffsetX,-500.0,500.0);
    gPhotoSlotOffsetY[0]=D(@"photoFrame1OffsetY",gIconOffsetY,-500.0,500.0);

    for(NSInteger i=1;i<4;i++) {
        NSInteger n=i+1;
        NSString *enabledKey=[NSString stringWithFormat:@"photoFrame%ldEnabled",(long)n];
        NSString *widthKey=[NSString stringWithFormat:@"photoFrame%ldWidth",(long)n];
        NSString *heightKey=[NSString stringWithFormat:@"photoFrame%ldHeight",(long)n];
        NSString *anchorKey=[NSString stringWithFormat:@"photoFrame%ldAnchorTarget",(long)n];
        NSString *positionKey=[NSString stringWithFormat:@"photoFrame%ldPosition",(long)n];
        NSString *xKey=[NSString stringWithFormat:@"photoFrame%ldOffsetX",(long)n];
        NSString *yKey=[NSString stringWithFormat:@"photoFrame%ldOffsetY",(long)n];
        gPhotoSlotEnabled[i]=B(enabledKey,NO);
        gPhotoSlotWidth[i]=D(widthKey,22.0,20.0,600.0);
        gPhotoSlotHeight[i]=D(heightKey,22.0,20.0,600.0);
        gPhotoSlotAnchor[i]=I(anchorKey,0);
        gPhotoSlotPosition[i]=I(positionKey,1);
        gPhotoSlotOffsetX[i]=D(xKey,0.0,-500.0,500.0);
        gPhotoSlotOffsetY[i]=D(yKey,0.0,-500.0,500.0);
    }
'''
if position_load not in runtime:
    raise SystemExit('icon position prefs load anchor not found')
runtime = runtime.replace(position_load, position_load + slot_load, 1)

photo_load_anchor = '''    id photo=[prefs objectForKey:@"customPhotoData"];
    gCustomPhotoData=[photo isKindOfClass:NSData.class]?photo:nil;
    gCustomPhotoImage=gCustomPhotoData.length?[UIImage imageWithData:gCustomPhotoData]:nil;'''
photo_load_new = photo_load_anchor + r'''

    gPhotoSlotData[0]=gCustomPhotoData;
    gPhotoSlotImage[0]=gCustomPhotoImage;
    for(NSInteger i=1;i<4;i++) {
        NSString *dataKey=[NSString stringWithFormat:@"customPhotoData%ld",(long)(i+1)];
        id slotData=[prefs objectForKey:dataKey];
        gPhotoSlotData[i]=[slotData isKindOfClass:NSData.class]?slotData:nil;
        gPhotoSlotImage[i]=gPhotoSlotData[i].length?[UIImage imageWithData:gPhotoSlotData[i]]:nil;
    }

    // One-time Frame 1 migration. Existing custom-photo users keep the exact
    // photo, width/height and old anchor/placement/offsets after upgrading.
    if(![prefs objectForKey:@"photoFrame1Enabled"]) {
        BOOL legacyEnabled=[gIconName isEqualToString:@"custom.photo"] && (gPhotoSlotImage[0] != nil);
        [prefs setBool:legacyEnabled forKey:@"photoFrame1Enabled"];
        gPhotoSlotEnabled[0]=legacyEnabled;
    }
    if(![prefs objectForKey:@"photoFrame1AnchorTarget"]) [prefs setInteger:gAnchorTarget forKey:@"photoFrame1AnchorTarget"];
    if(![prefs objectForKey:@"photoFrame1Position"]) [prefs setInteger:gIconPosition forKey:@"photoFrame1Position"];
    if(![prefs objectForKey:@"photoFrame1OffsetX"]) [prefs setDouble:gIconOffsetX forKey:@"photoFrame1OffsetX"];
    if(![prefs objectForKey:@"photoFrame1OffsetY"]) [prefs setDouble:gIconOffsetY forKey:@"photoFrame1OffsetY"];
    [prefs synchronize];'''
if photo_load_anchor not in runtime:
    raise SystemExit('custom photo data load anchor not found')
runtime = runtime.replace(photo_load_anchor, photo_load_new, 1)

# The legacy Icon Type = Custom Photo path becomes Frame 1. Suppress the old
# single icon-host renderer so Frame 1 is never duplicated.
icon_host_anchor = '    LGTIconHostView *host=objc_getAssociatedObject(container,LGTIconAssociationKey);'
if icon_host_anchor not in runtime:
    raise SystemExit('icon host anchor not found')
runtime = runtime.replace(icon_host_anchor, icon_host_anchor + r'''
    if([gIconName isEqualToString:@"custom.photo"]){
        [host removeFromSuperview];
        objc_setAssociatedObject(container,LGTIconAssociationKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }''', 1)

reset_container_anchor = 'static void LGTResetContainerBeforeAppleLayout(UIView *container) {'
photo_renderer = r'''
static CGRect LGTPhotoSlotFrame(CGRect anchor,CGFloat width,CGFloat height,NSInteger position,CGFloat offsetX,CGFloat offsetY) {
    CGFloat spacing=8.0;
    CGFloat x=CGRectGetMaxX(anchor)+spacing;
    CGFloat y=CGRectGetMidY(anchor)-height/2.0;
    if(position==0){
        x=CGRectGetMinX(anchor)-width-spacing;
        y=CGRectGetMidY(anchor)-height/2.0;
    } else if(position==2){
        x=CGRectGetMidX(anchor)-width/2.0;
        y=CGRectGetMinY(anchor)-height-spacing;
    } else if(position==3){
        x=CGRectGetMidX(anchor)-width/2.0;
        y=CGRectGetMaxY(anchor)+spacing;
    }
    return CGRectMake(x+offsetX,y+offsetY,width,height);
}

static void LGTRemovePhotoFrames(UIView *container) {
    if(!container)return;
    for(NSInteger i=0;i<4;i++) {
        const void *key=&LGTPhotoFrameAssociationKeys[i];
        UIView *host=objc_getAssociatedObject(container,key);
        [host removeFromSuperview];
        objc_setAssociatedObject(container,key,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void LGTApplyPhotoFrames(UIView *container,UILabel *time,UILabel *date) {
    if(!container)return;
    for(NSInteger i=0;i<4;i++) {
        const void *key=&LGTPhotoFrameAssociationKeys[i];
        LGTIconHostView *host=objc_getAssociatedObject(container,key);
        UIImage *image=gPhotoSlotImage[i];
        BOOL visible=gEnabled && gPhotoSlotEnabled[i] && image && time;
        if(!visible) {
            [host removeFromSuperview];
            objc_setAssociatedObject(container,key,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            continue;
        }
        if(!host) {
            host=[[LGTIconHostView alloc] initWithFrame:CGRectZero];
            [container addSubview:host];
            objc_setAssociatedObject(container,key,host,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIImageView *photoView=host.imageView;
        BOOL sticker=LGTImageHasVisibleTransparency(image);
        photoView.image=[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        photoView.tintColor=nil;
        photoView.layer.mask=nil;
        photoView.layer.cornerRadius=0;
        photoView.clipsToBounds=NO;
        if(sticker) {
            photoView.contentMode=UIViewContentModeScaleAspectFit;
        } else {
            photoView.contentMode=UIViewContentModeScaleAspectFill;
            photoView.layer.cornerRadius=MAX(4.0,MIN(gPhotoSlotWidth[i],gPhotoSlotHeight[i])*0.22);
            photoView.clipsToBounds=YES;
        }
        host.layer.shadowOpacity=gShadowEnabled?(float)gShadowOpacity:0;
        host.layer.shadowRadius=gShadowRadius;
        host.layer.shadowOffset=CGSizeMake(gShadowOffsetX,gShadowOffsetY);
        host.layer.shadowColor=(gIconShadowUIColor?:UIColor.blackColor).CGColor;
        host.layer.masksToBounds=NO;
        host.layer.shadowPath=nil;
        UILabel *anchor=(gPhotoSlotAnchor[i]==1&&date)?date:time;
        CGRect anchorFrame=[anchor convertRect:anchor.bounds toView:container];
        host.frame=LGTPhotoSlotFrame(anchorFrame,gPhotoSlotWidth[i],gPhotoSlotHeight[i],gPhotoSlotPosition[i],gPhotoSlotOffsetX[i],gPhotoSlotOffsetY[i]);
        photoView.frame=host.bounds;
        [container bringSubviewToFront:host];
    }
}

'''
if reset_container_anchor not in runtime:
    raise SystemExit('container reset anchor not found')
runtime = runtime.replace(reset_container_anchor, photo_renderer + reset_container_anchor, 1)

final_icon_anchor = '    LGTApplyIcon(container,time,date);'
if final_icon_anchor not in runtime:
    raise SystemExit('final geometry icon anchor not found')
runtime = runtime.replace(final_icon_anchor, final_icon_anchor + '\n    LGTApplyPhotoFrames(container,time,date);', 1)

no_time_old = '    if(!time){UIImageView *icon=objc_getAssociatedObject(container,LGTIconAssociationKey);[icon removeFromSuperview];return;}'
no_time_new = '    if(!time){UIView *icon=objc_getAssociatedObject(container,LGTIconAssociationKey);[icon removeFromSuperview];LGTRemovePhotoFrames(container);return;}'
if no_time_old not in runtime:
    raise SystemExit('no-time cleanup anchor not found')
runtime = runtime.replace(no_time_old,no_time_new,1)
runtime_path.write_text(runtime)

# ---------------------------------------------------------------------------
# Preferences: Custom Photo becomes a four-frame hub with a dedicated page for
# every frame so each one has its own photo, size and position controls.
# ---------------------------------------------------------------------------
photo_path = ROOT / 'prefs' / 'Resources' / 'Photo.plist'
photo = plistlib.loads(photo_path.read_bytes())
photo['items'] = [
    {
        'cell':'PSGroupCell',
        'label':'PHOTO FRAMES',
        'footerText':'Use up to four photos or transparent stickers at the same time. Every frame has completely independent width, height, anchor, placement and X/Y position.'
    },
    {'cell':'PSLinkCell','label':'Frame 1','detail':'LGTPhotoFrame1Controller'},
    {'cell':'PSLinkCell','label':'Frame 2','detail':'LGTPhotoFrame2Controller'},
    {'cell':'PSLinkCell','label':'Frame 3','detail':'LGTPhotoFrame3Controller'},
    {'cell':'PSLinkCell','label':'Frame 4','detail':'LGTPhotoFrame4Controller'},
    {
        'cell':'PSGroupCell',
        'label':'TIP',
        'footerText':'Frame 1 preserves the existing custom photo on upgrade. Frames 2–4 start disabled. Transparent PNGs stay sticker-style; opaque photos use rounded rectangular frames.'
    }
]
photo_path.write_bytes(plistlib.dumps(photo,fmt=plistlib.FMT_XML,sort_keys=False))

DOMAIN='com.nextsolution.lockglyphtime'
NOTIFY='com.nextsolution.lockglyphtime/ReloadPrefs'
resources=ROOT/'prefs'/'Resources'

def group(label,footer=None):
    d={'cell':'PSGroupCell','label':label}
    if footer:d['footerText']=footer
    return d

def switch(label,key,default=False):
    return {'cell':'PSSwitchCell','label':label,'defaults':DOMAIN,'key':key,'default':default,'PostNotification':NOTIFY}

def slider(label,key,default,mn,mx):
    return {'cell':'PSSliderCell','label':label,'defaults':DOMAIN,'key':key,'default':default,'min':mn,'max':mx,'showValue':True,'PostNotification':NOTIFY}

def choice(label,key,default,titles,values):
    return {'cell':'PSLinkListCell','detail':'PSListItemsController','label':label,'defaults':DOMAIN,'key':key,'default':default,'validTitles':titles,'validValues':values,'PostNotification':NOTIFY}

def button(label,action):
    return {'cell':'PSButtonCell','label':label,'action':action}

def frame_page(n):
    width_key='photoFrameWidth' if n==1 else f'photoFrame{n}Width'
    height_key='photoFrameHeight' if n==1 else f'photoFrame{n}Height'
    return {
        'title':f'Frame {n}',
        'items':[
            group(f'FRAME {n}', 'This frame is independent from every other photo frame. Choosing a photo automatically enables it.'),
            switch(f'Enable Frame {n}',f'photoFrame{n}Enabled',False),
            button('Choose / Edit Photo',f'openCustomPhotoPickerFrame{n}'),
            button('Remove Photo',f'removeCustomPhotoFrame{n}'),
            group('SIZE','Width and height can be adjusted independently from 20–600pt.'),
            slider('Width',width_key,22,20,600),
            slider('Height',height_key,22,20,600),
            group('POSITION','Anchor the frame to the Time or Date, choose a side, then fine-tune its X/Y position.'),
            choice('Anchor To',f'photoFrame{n}AnchorTarget',0,['Time','Date'],[0,1]),
            choice('Placement',f'photoFrame{n}Position',1,['Left','Right','Above','Below'],[0,1,2,3]),
            slider('Horizontal Offset',f'photoFrame{n}OffsetX',0,-500,500),
            slider('Vertical Offset',f'photoFrame{n}OffsetY',0,-500,500),
        ]
    }

for n in range(1,5):
    (resources/f'PhotoFrame{n}.plist').write_bytes(plistlib.dumps(frame_page(n),fmt=plistlib.FMT_XML,sort_keys=False))

# Picker routing: remember which frame opened PHPicker, then save/remove only
# that frame's image and enable state.
prop_anchor='@property(nonatomic,copy) NSString *activeColorKey;'
if prop_anchor not in prefs:
    raise SystemExit('prefs activeColorKey property anchor not found')
prefs=prefs.replace(prop_anchor,prop_anchor+'\n@property(nonatomic,assign) NSInteger activePhotoFrame;',1)

open_start=prefs.index('- (void)openCustomPhotoPicker {')
picker_start=prefs.index('- (void)picker:(PHPickerViewController *)picker didFinishPicking:',open_start)
open_methods=r'''- (NSString *)lgt_photoDataKeyForFrame:(NSInteger)frame {
    NSInteger n=MAX(1,MIN(4,frame));
    return n==1?@"customPhotoData":[NSString stringWithFormat:@"customPhotoData%ld",(long)n];
}
- (NSString *)lgt_photoEnabledKeyForFrame:(NSInteger)frame {
    NSInteger n=MAX(1,MIN(4,frame));
    return [NSString stringWithFormat:@"photoFrame%ldEnabled",(long)n];
}
- (void)lgt_openCustomPhotoPickerForFrame:(NSInteger)frame {
    self.activePhotoFrame=MAX(1,MIN(4,frame));
    PHPickerConfiguration *config=[[PHPickerConfiguration alloc] init];
    config.selectionLimit=1;
    config.filter=[PHPickerFilter imagesFilter];
    PHPickerViewController *picker=[[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate=self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)openCustomPhotoPicker { [self lgt_openCustomPhotoPickerForFrame:1]; }
- (void)openCustomPhotoPickerFrame1 { [self lgt_openCustomPhotoPickerForFrame:1]; }
- (void)openCustomPhotoPickerFrame2 { [self lgt_openCustomPhotoPickerForFrame:2]; }
- (void)openCustomPhotoPickerFrame3 { [self lgt_openCustomPhotoPickerForFrame:3]; }
- (void)openCustomPhotoPickerFrame4 { [self lgt_openCustomPhotoPickerForFrame:4]; }
'''
prefs=prefs[:open_start]+open_methods+'\n'+prefs[picker_start:]

picker_start=prefs.index('- (void)picker:(PHPickerViewController *)picker didFinishPicking:')
remove_start=prefs.index('- (void)removeCustomPhoto {',picker_start)
picker_method=r'''- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result=results.firstObject;
    if(!result)return;
    NSItemProvider *provider=result.itemProvider;
    if(![provider canLoadObjectOfClass:UIImage.class])return;
    NSInteger frame=MAX(1,MIN(4,self.activePhotoFrame?:1));
    __weak typeof(self) weakSelf=self;
    [provider loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object,NSError *error){
        if(error||![object isKindOfClass:UIImage.class])return;
        dispatch_async(dispatch_get_main_queue(),^{
            typeof(self) selfRef=weakSelf;
            if(!selfRef)return;
            LGTPhotoCropController *editor=[[LGTPhotoCropController alloc] initWithImage:(UIImage *)object completion:^(UIImage *image){
                NSData *data=UIImagePNGRepresentation(image);
                if(!data)return;
                NSUserDefaults *p=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];
                [p setObject:data forKey:[selfRef lgt_photoDataKeyForFrame:frame]];
                [p setBool:YES forKey:[selfRef lgt_photoEnabledKeyForFrame:frame]];
                [p synchronize];
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),LGTReloadNotification,NULL,NULL,true);
                [selfRef reloadSpecifiers];
            }];
            UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:editor];
            [selfRef presentViewController:nav animated:YES completion:nil];
        });
    }];
}
'''
prefs=prefs[:picker_start]+picker_method+'\n'+prefs[remove_start:]

remove_start=prefs.index('- (void)removeCustomPhoto {')
viewdid_start=prefs.index('\n- (void)viewDidLoad',remove_start)
remove_methods=r'''- (void)lgt_removeCustomPhotoFrame:(NSInteger)frame {
    NSInteger n=MAX(1,MIN(4,frame));
    NSUserDefaults *p=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];
    [p removeObjectForKey:[self lgt_photoDataKeyForFrame:n]];
    [p setBool:NO forKey:[self lgt_photoEnabledKeyForFrame:n]];
    [p synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),LGTReloadNotification,NULL,NULL,true);
    [self reloadSpecifiers];
}
- (void)removeCustomPhoto { [self lgt_removeCustomPhotoFrame:1]; }
- (void)removeCustomPhotoFrame1 { [self lgt_removeCustomPhotoFrame:1]; }
- (void)removeCustomPhotoFrame2 { [self lgt_removeCustomPhotoFrame:2]; }
- (void)removeCustomPhotoFrame3 { [self lgt_removeCustomPhotoFrame:3]; }
- (void)removeCustomPhotoFrame4 { [self lgt_removeCustomPhotoFrame:4]; }
'''
prefs=prefs[:remove_start]+remove_methods+prefs[viewdid_start:]

# Reset Icon historically also reset Custom Photo, so keep that behavior for all
# four frames rather than leaving hidden frame data behind.
reset_start=prefs.index('- (void)resetIcon {')
reset_end=prefs.index('\n- (void)resetAll {',reset_start)
frame_keys=[]
for n in range(1,5):
    frame_keys += [f'photoFrame{n}Enabled',f'photoFrame{n}AnchorTarget',f'photoFrame{n}Position',f'photoFrame{n}OffsetX',f'photoFrame{n}OffsetY']
    if n>1: frame_keys += [f'photoFrame{n}Width',f'photoFrame{n}Height',f'customPhotoData{n}']
frame_keys += ['photoFrameSize','photoFrameWidth','photoFrameHeight','customPhotoData']
base_keys=['iconEnabled','iconName','iconSize','iconColor','anchorTarget','iconPosition','iconOffsetX','iconOffsetY','shadowEnabled','shadowColor','shadowOpacity','shadowRadius','shadowOffsetX','shadowOffsetY']
objc_keys=','.join('@"'+k+'"' for k in base_keys+frame_keys)
reset_method='- (void)resetIcon { [self resetKeys:@['+objc_keys+']]; }'
prefs=prefs[:reset_start]+reset_method+prefs[reset_end:]

# Dedicated frame controllers.
prefs += r'''

@interface LGTPhotoFrame1Controller : LGTListController @end
@implementation LGTPhotoFrame1Controller
- (NSString *)lgt_plistName { return @"PhotoFrame1"; }
@end
@interface LGTPhotoFrame2Controller : LGTListController @end
@implementation LGTPhotoFrame2Controller
- (NSString *)lgt_plistName { return @"PhotoFrame2"; }
@end
@interface LGTPhotoFrame3Controller : LGTListController @end
@implementation LGTPhotoFrame3Controller
- (NSString *)lgt_plistName { return @"PhotoFrame3"; }
@end
@interface LGTPhotoFrame4Controller : LGTListController @end
@implementation LGTPhotoFrame4Controller
- (NSString *)lgt_plistName { return @"PhotoFrame4"; }
@end
'''
prefs_path.write_text(prefs)

# ---------------------------------------------------------------------------
# Version metadata: 1.1.4 public multi-frame release.
# ---------------------------------------------------------------------------
control_path=ROOT/'control'
control=control_path.read_text().replace('Version: 1.1.3','Version: 1.1.4',1)
lines=control.splitlines()
for i,line in enumerate(lines):
    if line.startswith('Description:'):
        lines[i]='Description: Next Solution lock-screen customization suite. Version 1.1.4 adds four simultaneous custom-photo/sticker frames, each with its own image, width, height, anchor, placement and X/Y position controls.'
        break
control_path.write_text('\n'.join(lines)+'\n')

info_path=resources/'Info.plist'
info=plistlib.loads(info_path.read_bytes())
info['CFBundleShortVersionString']='1.1.4'
info['CFBundleVersion']='114'
info_path.write_bytes(plistlib.dumps(info,fmt=plistlib.FMT_XML,sort_keys=False))

about_path=resources/'About.plist'
about=plistlib.loads(about_path.read_bytes())
for item in about.get('items',[]):
    footer=item.get('footerText')
    if isinstance(footer,str):
        item['footerText']=footer.replace('Version 1.1.3','Version 1.1.4')
about_path.write_bytes(plistlib.dumps(about,fmt=plistlib.FMT_XML,sort_keys=False))

print('Patched NextLock 1.1.4: four independent custom photo frames')
