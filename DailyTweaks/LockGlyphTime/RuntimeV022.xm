#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString * const LGTPrefsDomain = @"com.nextsolution.lockglyphtime";
static CFStringRef const LGTReloadNotification = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");
static const void *LGTIconAssociationKey = &LGTIconAssociationKey;
static const void *LGTLabelStateAssociationKey = &LGTLabelStateAssociationKey;

@interface LGTLabelState : NSObject
@property(nonatomic, assign) CGAffineTransform nativeTransform;
@property(nonatomic, assign) CGPoint nativeCenter;
@property(nonatomic, assign) BOOL hasNativeCenter;
@property(nonatomic, assign) BOOL hasAppliedPosition;
@property(nonatomic, strong) UIFont *nativeFont;
@property(nonatomic, strong) UIColor *nativeTextColor;
@property(nonatomic, assign) NSTextAlignment nativeAlignment;
@property(nonatomic, copy) NSString *nativeText;
@property(nonatomic, strong) NSAttributedString *nativeAttributedText;
@property(nonatomic, strong) UIColor *nativeShadowColor;
@property(nonatomic, assign) CGSize nativeShadowOffset;
@property(nonatomic, strong) UIColor *nativeLayerShadowColor;
@property(nonatomic, assign) float nativeLayerShadowOpacity;
@property(nonatomic, assign) CGFloat nativeLayerShadowRadius;
@property(nonatomic, assign) CGSize nativeLayerShadowOffset;
@end
@implementation LGTLabelState
@end

static BOOL gEnabled = YES;

// Time
static BOOL gCustomTimeEnabled = YES;
static CGFloat gTimeScale = 1.0;
static NSString *gTimeColor = @"#FFFFFF";
static CGFloat gTimeOffsetX = 0.0;
static CGFloat gTimeOffsetY = 0.0;
static NSInteger gTimeAlignment = 0;
static NSString *gTimeFont = @"Original";
static NSInteger gTimeFontWeight = 3;
static NSInteger gTimeStyle = 0;
static BOOL gTimeShadowEnabled = NO;
static NSString *gTimeShadowColor = @"#000000";
static CGFloat gTimeShadowOpacity = 0.45;
static CGFloat gTimeShadowRadius = 2.0;
static CGFloat gTimeShadowOffsetX = 0.0;
static CGFloat gTimeShadowOffsetY = 1.0;

// Date
static BOOL gCustomDateEnabled = YES;
static CGFloat gDateScale = 1.0;
static NSString *gDateColor = @"#FFFFFF";
static CGFloat gDateOffsetX = 0.0;
static CGFloat gDateOffsetY = 0.0;
static NSInteger gDateAlignment = 0;
static NSString *gDateFont = @"Original";
static NSInteger gDateFontWeight = 3;
static NSInteger gDateStyle = 0;
static NSString *gDateFormat = @"system";
static NSString *gCustomDateFormat = @"EEEE, MMMM d";
static BOOL gDateShadowEnabled = NO;
static NSString *gDateShadowColor = @"#000000";
static CGFloat gDateShadowOpacity = 0.45;
static CGFloat gDateShadowRadius = 2.0;
static CGFloat gDateShadowOffsetX = 0.0;
static CGFloat gDateShadowOffsetY = 1.0;

// Icon - legacy keys remain unchanged
static BOOL gIconEnabled = YES;
static NSString *gIconName = @"sparkles";
static CGFloat gIconSize = 22.0;
static NSString *gIconColor = @"#FFFFFF";
static NSInteger gAnchorTarget = 0;
static NSInteger gIconPosition = 1;
static CGFloat gIconOffsetX = 0.0;
static CGFloat gIconOffsetY = 0.0;
static BOOL gShadowEnabled = YES;
static NSString *gShadowColor = @"#000000";
static CGFloat gShadowOpacity = 0.45;
static CGFloat gShadowRadius = 2.0;
static CGFloat gShadowOffsetX = 0.0;
static CGFloat gShadowOffsetY = 1.0;
static NSData *gCustomPhotoData = nil;
static UIImage *gCustomPhotoImage = nil;

static UIColor *gTimeUIColor;
static UIColor *gDateUIColor;
static UIColor *gTimeShadowUIColor;
static UIColor *gDateShadowUIColor;
static UIColor *gIconUIColor;
static UIColor *gIconShadowUIColor;
static NSDateFormatter *gDateFormatter;
static NSMutableDictionary<NSString *, UIFont *> *gFontCache;
static NSHashTable<UIView *> *gKnownContainers;

static CGFloat LGTClamped(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return MAX(minimum, MIN(maximum, value));
}

static UIColor *LGTColorFromHex(NSString *hex, UIColor *fallback) {
    if (![hex isKindOfClass:NSString.class]) return fallback;
    NSString *clean = [[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if (clean.length == 3) {
        unichar r=[clean characterAtIndex:0], g=[clean characterAtIndex:1], b=[clean characterAtIndex:2];
        clean = [NSString stringWithFormat:@"%C%C%C%C%C%C",r,r,g,g,b,b];
    }
    if (clean.length != 6 && clean.length != 8) return fallback;
    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexLongLong:&value] || !scanner.isAtEnd) return fallback;
    CGFloat r,g,b,a=1.0;
    if (clean.length == 8) {
        r=((value>>24)&0xFF)/255.0; g=((value>>16)&0xFF)/255.0; b=((value>>8)&0xFF)/255.0; a=(value&0xFF)/255.0;
    } else {
        r=((value>>16)&0xFF)/255.0; g=((value>>8)&0xFF)/255.0; b=(value&0xFF)/255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static UIFontWeight LGTWeightForValue(NSInteger value) {
    switch (value) {
        case 0:return UIFontWeightUltraLight; case 1:return UIFontWeightThin; case 2:return UIFontWeightLight;
        case 4:return UIFontWeightMedium; case 5:return UIFontWeightSemibold; case 6:return UIFontWeightBold;
        case 7:return UIFontWeightHeavy; case 8:return UIFontWeightBlack; default:return UIFontWeightRegular;
    }
}

static UIFontDescriptorSymbolicTraits LGTStyleTraits(NSInteger style) {
    switch (style) {
        case 2:return UIFontDescriptorTraitBold;
        case 3:return UIFontDescriptorTraitItalic;
        case 4:return UIFontDescriptorTraitBold|UIFontDescriptorTraitItalic;
        default:return 0;
    }
}

static BOOL LGTUsesSystemFamily(NSString *name) {
    return [name isEqualToString:@"System"] || [name isEqualToString:@"System Rounded"] ||
           [name isEqualToString:@"System Serif / New York"] || [name isEqualToString:@"System Monospaced"];
}

static UIFont *LGTSafeFont(NSString *fontName, CGFloat size, NSInteger weight, NSInteger style, UIFont *fallback) {
    if (!fallback) fallback = [UIFont systemFontOfSize:MAX(size,12.0)];
    NSString *name = fontName.length ? fontName : @"Original";
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%.2f|%ld|%ld|%@",name,size,(long)weight,(long)style,fallback.fontName?:@"fallback"];
    UIFont *cached = gFontCache[cacheKey];
    if (cached) return cached;
    UIFont *font=nil;
    UIFontDescriptorSymbolicTraits traits=LGTStyleTraits(style);
    if ([name isEqualToString:@"Original"]) {
        font=fallback;
    } else if (LGTUsesSystemFamily(name)) {
        UIFont *base=[UIFont systemFontOfSize:MAX(size,1.0) weight:LGTWeightForValue(weight)];
        UIFontDescriptor *descriptor=base.fontDescriptor;
        if ([name isEqualToString:@"System Rounded"]) {
            UIFontDescriptor *d=[descriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded]; if(d) descriptor=d;
        } else if ([name isEqualToString:@"System Serif / New York"]) {
            UIFontDescriptor *d=[descriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignSerif]; if(d) descriptor=d;
        } else if ([name isEqualToString:@"System Monospaced"]) {
            UIFontDescriptor *d=[descriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignMonospaced]; if(d) descriptor=d;
        }
        if (traits) { UIFontDescriptor *d=[descriptor fontDescriptorWithSymbolicTraits:(descriptor.symbolicTraits|traits)]; if(d) descriptor=d; }
        font=[UIFont fontWithDescriptor:descriptor size:MAX(size,1.0)];
    } else {
        font=[UIFont fontWithName:name size:MAX(size,1.0)];
        if (font && traits) { UIFontDescriptor *d=[font.fontDescriptor fontDescriptorWithSymbolicTraits:(font.fontDescriptor.symbolicTraits|traits)]; if(d) font=[UIFont fontWithDescriptor:d size:MAX(size,1.0)]; }
    }
    if (!font) font=fallback;
    if (font) gFontCache[cacheKey]=font;
    return font;
}

static NSTextAlignment LGTAlignmentForValue(NSInteger value, NSTextAlignment fallback) {
    switch (value) { case 1:return NSTextAlignmentLeft; case 2:return NSTextAlignmentCenter; case 3:return NSTextAlignmentRight; default:return fallback; }
}

static LGTLabelState *LGTStateForLabel(UILabel *label) {
    if (!label) return nil;
    LGTLabelState *state=objc_getAssociatedObject(label,LGTLabelStateAssociationKey);
    if (!state) {
        state=[LGTLabelState new];
        state.nativeTransform=label.transform;
        state.nativeFont=label.font?:[UIFont systemFontOfSize:17.0];
        state.nativeTextColor=label.textColor?:UIColor.whiteColor;
        state.nativeAlignment=label.textAlignment;
        state.nativeText=label.text;
        state.nativeAttributedText=label.attributedText;
        state.nativeShadowColor=label.shadowColor;
        state.nativeShadowOffset=label.shadowOffset;
        state.nativeLayerShadowColor=label.layer.shadowColor?[UIColor colorWithCGColor:label.layer.shadowColor]:nil;
        state.nativeLayerShadowOpacity=label.layer.shadowOpacity;
        state.nativeLayerShadowRadius=label.layer.shadowRadius;
        state.nativeLayerShadowOffset=label.layer.shadowOffset;
        state.nativeCenter=label.center;
        state.hasNativeCenter=YES;
        objc_setAssociatedObject(label,LGTLabelStateAssociationKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static void LGTRestoreBeforeAppleLayout(UILabel *label) {
    LGTLabelState *state=objc_getAssociatedObject(label,LGTLabelStateAssociationKey);
    if (!state) return;
    if (state.hasAppliedPosition && state.hasNativeCenter) label.center=state.nativeCenter;
    state.hasAppliedPosition=NO;
    label.transform=state.nativeTransform;
    label.font=state.nativeFont;
    label.textColor=state.nativeTextColor;
    label.textAlignment=state.nativeAlignment;
    if (state.nativeAttributedText) label.attributedText=state.nativeAttributedText; else label.text=state.nativeText;
    label.shadowColor=state.nativeShadowColor;
    label.shadowOffset=state.nativeShadowOffset;
    label.layer.shadowColor=state.nativeLayerShadowColor.CGColor;
    label.layer.shadowOpacity=state.nativeLayerShadowOpacity;
    label.layer.shadowRadius=state.nativeLayerShadowRadius;
    label.layer.shadowOffset=state.nativeLayerShadowOffset;
}

static void LGTCaptureNativeAfterAppleLayout(UILabel *label) {
    LGTLabelState *state=LGTStateForLabel(label);
    state.nativeTransform=label.transform;
    state.nativeFont=label.font?:state.nativeFont;
    state.nativeTextColor=label.textColor?:state.nativeTextColor;
    state.nativeAlignment=label.textAlignment;
    state.nativeText=label.text;
    state.nativeAttributedText=label.attributedText;
    state.nativeShadowColor=label.shadowColor;
    state.nativeShadowOffset=label.shadowOffset;
    state.nativeLayerShadowColor=label.layer.shadowColor?[UIColor colorWithCGColor:label.layer.shadowColor]:nil;
    state.nativeLayerShadowOpacity=label.layer.shadowOpacity;
    state.nativeLayerShadowRadius=label.layer.shadowRadius;
    state.nativeLayerShadowOffset=label.layer.shadowOffset;
    state.nativeCenter=label.center;
    state.hasNativeCenter=YES;
}

static void LGTRestoreCapturedState(UILabel *label,LGTLabelState *state) {
    if (!label||!state) return;
    label.center=state.nativeCenter;
    label.transform=state.nativeTransform;
    label.font=state.nativeFont;
    label.textColor=state.nativeTextColor;
    label.textAlignment=state.nativeAlignment;
    if (state.nativeAttributedText) label.attributedText=state.nativeAttributedText; else label.text=state.nativeText;
    label.shadowColor=state.nativeShadowColor;
    label.shadowOffset=state.nativeShadowOffset;
    label.layer.shadowColor=state.nativeLayerShadowColor.CGColor;
    label.layer.shadowOpacity=state.nativeLayerShadowOpacity;
    label.layer.shadowRadius=state.nativeLayerShadowRadius;
    label.layer.shadowOffset=state.nativeLayerShadowOffset;
    state.hasAppliedPosition=NO;
}

static void LGTConfigureDateFormatter(void) {
    gDateFormatter=nil;
    if ([gDateFormat isEqualToString:@"system"]) return;
    NSString *format=[gDateFormat isEqualToString:@"custom"]?gCustomDateFormat:gDateFormat;
    if (!format.length) return;
    NSDateFormatter *formatter=[NSDateFormatter new];
    formatter.locale=NSLocale.currentLocale; formatter.calendar=NSCalendar.currentCalendar; formatter.timeZone=NSTimeZone.localTimeZone; formatter.dateFormat=format;
    gDateFormatter=formatter;
}

static void LGTRequestRelayout(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        for (UIView *view in gKnownContainers.allObjects) { [view setNeedsLayout]; [view layoutIfNeeded]; }
    });
}

static void LGTLoadPrefs(void) {
    NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];
    id value; NSString *s;
#define B(KEY,DEF) ((value=[prefs objectForKey:(KEY)])?[value boolValue]:(DEF))
#define D(KEY,DEF,MIN,MAX) ((value=[prefs objectForKey:(KEY)])?LGTClamped([value doubleValue],(MIN),(MAX)):(DEF))
#define I(KEY,DEF) ((value=[prefs objectForKey:(KEY)])?[value integerValue]:(DEF))
#define S(KEY,DEF) ((s=[prefs stringForKey:(KEY)])&&s.length?s:(DEF))
    gEnabled=B(@"enabled",YES);
    gCustomTimeEnabled=B(@"customTimeEnabled",YES); gTimeScale=D(@"timeScale",1.0,0.5,2.5); gTimeColor=S(@"timeColor",@"#FFFFFF");
    gTimeOffsetX=D(@"timeOffsetX",0.0,-150.0,150.0); gTimeOffsetY=D(@"timeOffsetY",0.0,-150.0,150.0); gTimeAlignment=I(@"timeAlignment",0);
    gTimeFont=S(@"timeFont",@"Original"); gTimeFontWeight=I(@"timeFontWeight",3); gTimeStyle=I(@"timeStyle",0);
    gTimeShadowEnabled=B(@"timeShadowEnabled",NO); gTimeShadowColor=S(@"timeShadowColor",@"#000000"); gTimeShadowOpacity=D(@"timeShadowOpacity",0.45,0.0,1.0);
    gTimeShadowRadius=D(@"timeShadowRadius",2.0,0.0,20.0); gTimeShadowOffsetX=D(@"timeShadowOffsetX",0.0,-20.0,20.0); gTimeShadowOffsetY=D(@"timeShadowOffsetY",1.0,-20.0,20.0);

    gCustomDateEnabled=B(@"customDateEnabled",YES); gDateScale=D(@"dateScale",1.0,0.5,2.5); gDateColor=S(@"dateColor",@"#FFFFFF");
    gDateOffsetX=D(@"dateOffsetX",0.0,-150.0,150.0); gDateOffsetY=D(@"dateOffsetY",0.0,-150.0,150.0); gDateAlignment=I(@"dateAlignment",0);
    gDateFont=S(@"dateFont",@"Original"); gDateFontWeight=I(@"dateFontWeight",3); gDateStyle=I(@"dateStyle",0); gDateFormat=S(@"dateFormat",@"system"); gCustomDateFormat=S(@"customDateFormat",@"EEEE, MMMM d");
    gDateShadowEnabled=B(@"dateShadowEnabled",NO); gDateShadowColor=S(@"dateShadowColor",@"#000000"); gDateShadowOpacity=D(@"dateShadowOpacity",0.45,0.0,1.0);
    gDateShadowRadius=D(@"dateShadowRadius",2.0,0.0,20.0); gDateShadowOffsetX=D(@"dateShadowOffsetX",0.0,-20.0,20.0); gDateShadowOffsetY=D(@"dateShadowOffsetY",1.0,-20.0,20.0);

    gIconEnabled=B(@"iconEnabled",YES); gIconName=S(@"iconName",@"sparkles"); gIconSize=D(@"iconSize",22.0,10.0,80.0); gIconColor=S(@"iconColor",@"#FFFFFF");
    gAnchorTarget=I(@"anchorTarget",0); gIconPosition=I(@"iconPosition",1); gIconOffsetX=D(@"iconOffsetX",0.0,-120.0,120.0); gIconOffsetY=D(@"iconOffsetY",0.0,-120.0,120.0);
    gShadowEnabled=B(@"shadowEnabled",YES); gShadowColor=S(@"shadowColor",@"#000000"); gShadowOpacity=D(@"shadowOpacity",0.45,0.0,1.0); gShadowRadius=D(@"shadowRadius",2.0,0.0,20.0);
    gShadowOffsetX=D(@"shadowOffsetX",0.0,-20.0,20.0); gShadowOffsetY=D(@"shadowOffsetY",1.0,-20.0,20.0);
#undef B
#undef D
#undef I
#undef S
    id photo=[prefs objectForKey:@"customPhotoData"];
    gCustomPhotoData=[photo isKindOfClass:NSData.class]?photo:nil;
    gCustomPhotoImage=gCustomPhotoData.length?[UIImage imageWithData:gCustomPhotoData]:nil;

    [gFontCache removeAllObjects];
    gTimeUIColor=LGTColorFromHex(gTimeColor,UIColor.whiteColor); gDateUIColor=LGTColorFromHex(gDateColor,UIColor.whiteColor);
    gTimeShadowUIColor=LGTColorFromHex(gTimeShadowColor,UIColor.blackColor); gDateShadowUIColor=LGTColorFromHex(gDateShadowColor,UIColor.blackColor);
    gIconUIColor=LGTColorFromHex(gIconColor,UIColor.whiteColor); gIconShadowUIColor=LGTColorFromHex(gShadowColor,UIColor.blackColor);
    LGTConfigureDateFormatter();
}

static void LGTReloadCallback(CFNotificationCenterRef c,void *o,CFStringRef n,const void *obj,CFDictionaryRef info) { LGTLoadPrefs(); LGTRequestRelayout(); }

static void LGTCollectLabels(UIView *view,NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view;
        if ((label.text.length||label.attributedText.length)&&label.font.pointSize>0&&!label.hidden) [labels addObject:label];
    }
    for (UIView *sub in view.subviews) LGTCollectLabels(sub,labels);
}

static NSString *LGTProbe(UILabel *label) {
    NSMutableArray *parts=[NSMutableArray array];
    if (label.accessibilityIdentifier.length) [parts addObject:label.accessibilityIdentifier];
    if (label.accessibilityLabel.length) [parts addObject:label.accessibilityLabel];
    [parts addObject:NSStringFromClass(label.class)]; if(label.superview)[parts addObject:NSStringFromClass(label.superview.class)];
    return [[parts componentsJoinedByString:@" "] lowercaseString];
}

static NSInteger LGTTimeScore(UILabel *label) {
    NSInteger score=(NSInteger)round(label.font.pointSize*10.0); NSString *text=label.text?:label.attributedText.string?:@""; NSString *probe=LGTProbe(label);
    if([probe containsString:@"time"])score+=1000; if([probe containsString:@"clock"])score+=800; if([probe containsString:@"date"])score-=500;
    NSUInteger digits=0; for(NSUInteger i=0;i<text.length;i++) if([NSCharacterSet.decimalDigitCharacterSet characterIsMember:[text characterAtIndex:i]]) digits++;
    if(digits>=3&&([text containsString:@":"]||[text containsString:@"."]))score+=1500; if(digits>=3)score+=250; return score;
}

static NSInteger LGTDateScore(UILabel *label) {
    NSInteger score=(NSInteger)round(label.font.pointSize*8.0); NSString *text=label.text?:label.attributedText.string?:@""; NSString *probe=LGTProbe(label);
    if([probe containsString:@"date"])score+=1200; if([probe containsString:@"subtitle"])score+=350; if([probe containsString:@"time"]||[probe containsString:@"clock"])score-=800;
    NSUInteger letters=0; for(NSUInteger i=0;i<text.length;i++) if([NSCharacterSet.letterCharacterSet characterIsMember:[text characterAtIndex:i]])letters++;
    if(letters>=3)score+=500; if([text containsString:@":"])score-=700; return score;
}

static void LGTResolveLabels(UIView *container,UILabel **timeOut,UILabel **dateOut) {
    NSMutableArray<UILabel *> *labels=[NSMutableArray array]; LGTCollectLabels(container,labels);
    UILabel *time=nil,*date=nil; NSInteger ts=NSIntegerMin,ds=NSIntegerMin;
    for(UILabel *label in labels){NSInteger s=LGTTimeScore(label);if(s>ts){ts=s;time=label;}}
    for(UILabel *label in labels){if(label==time)continue;NSInteger s=LGTDateScore(label);if(s>ds){ds=s;date=label;}}
    if(!time&&labels.count){[labels sortUsingComparator:^NSComparisonResult(UILabel *a,UILabel *b){return a.font.pointSize>b.font.pointSize?NSOrderedAscending:(a.font.pointSize<b.font.pointSize?NSOrderedDescending:NSOrderedSame);}];time=labels.firstObject;if(labels.count>1)date=labels[1];}
    if(timeOut)*timeOut=time;if(dateOut)*dateOut=date;
}

static void LGTApplyAttributedStyle(UILabel *label,UIFont *font,UIColor *color,NSInteger style,BOOL isDate) {
    NSString *text=label.text?:label.attributedText.string?:@""; if(isDate&&style==5)text=text.uppercaseString;else if(isDate&&style==6)text=text.lowercaseString;
    NSMutableDictionary *attrs=[@{NSFontAttributeName:font?:label.font,NSForegroundColorAttributeName:color?:label.textColor} mutableCopy];
    NSInteger outline=isDate?7:5; if(style==outline){attrs[NSStrokeColorAttributeName]=color?:label.textColor;attrs[NSStrokeWidthAttributeName]=@(-2.5);} label.attributedText=[[NSAttributedString alloc] initWithString:text attributes:attrs];
}

static void LGTApplyLayerShadow(UILabel *label,BOOL enabled,UIColor *color,CGFloat opacity,CGFloat radius,CGFloat x,CGFloat y,NSInteger style,BOOL isDate,UIColor *textColor) {
    if(enabled){label.layer.shadowColor=color.CGColor;label.layer.shadowOpacity=(float)opacity;label.layer.shadowRadius=radius;label.layer.shadowOffset=CGSizeMake(x,y);}
    else if(style==(isDate?8:6)){label.layer.shadowColor=UIColor.blackColor.CGColor;label.layer.shadowOpacity=.60f;label.layer.shadowRadius=2;label.layer.shadowOffset=CGSizeMake(0,1);}
    else if(style==(isDate?9:7)){label.layer.shadowColor=textColor.CGColor;label.layer.shadowOpacity=.85f;label.layer.shadowRadius=6;label.layer.shadowOffset=CGSizeZero;}
    label.layer.masksToBounds=NO;
}

static void LGTApplyTimeAppearance(UILabel *label) {
    if(!label)return; LGTLabelState *state=LGTStateForLabel(label); if(!gEnabled||!gCustomTimeEnabled){LGTRestoreCapturedState(label,state);return;}
    UIColor *color=gTimeUIColor?:state.nativeTextColor?:UIColor.whiteColor; UIFont *font=LGTSafeFont(gTimeFont,state.nativeFont.pointSize,gTimeFontWeight,gTimeStyle,state.nativeFont);
    label.font=font; label.textColor=color; label.textAlignment=LGTAlignmentForValue(gTimeAlignment,state.nativeAlignment);
    LGTApplyAttributedStyle(label,font,color,gTimeStyle,NO);
    label.transform=CGAffineTransformScale(state.nativeTransform,gTimeScale,gTimeScale);
    LGTApplyLayerShadow(label,gTimeShadowEnabled,gTimeShadowUIColor?:UIColor.blackColor,gTimeShadowOpacity,gTimeShadowRadius,gTimeShadowOffsetX,gTimeShadowOffsetY,gTimeStyle,NO,color);
}

static void LGTApplyDateAppearance(UILabel *label) {
    if(!label)return; LGTLabelState *state=LGTStateForLabel(label); if(!gEnabled||!gCustomDateEnabled){LGTRestoreCapturedState(label,state);return;}
    if(gDateFormatter){NSString *formatted=[gDateFormatter stringFromDate:[NSDate date]];if(formatted.length)label.text=formatted;}
    UIColor *color=gDateUIColor?:state.nativeTextColor?:UIColor.whiteColor; UIFont *font=LGTSafeFont(gDateFont,state.nativeFont.pointSize,gDateFontWeight,gDateStyle,state.nativeFont);
    label.font=font; label.textColor=color; label.textAlignment=LGTAlignmentForValue(gDateAlignment,state.nativeAlignment);
    LGTApplyAttributedStyle(label,font,color,gDateStyle,YES);
    label.transform=CGAffineTransformScale(state.nativeTransform,gDateScale,gDateScale);
    LGTApplyLayerShadow(label,gDateShadowEnabled,gDateShadowUIColor?:UIColor.blackColor,gDateShadowOpacity,gDateShadowRadius,gDateShadowOffsetX,gDateShadowOffsetY,gDateStyle,YES,color);
}

static void LGTApplyFinalPosition(UILabel *label,CGFloat x,CGFloat y) {
    if(!label)return; LGTLabelState *state=LGTStateForLabel(label); if(!state.hasNativeCenter)return;
    label.center=CGPointMake(state.nativeCenter.x+x,state.nativeCenter.y+y); state.hasAppliedPosition=YES;
}

static UIImage *LGTIconImage(void) {
    if([gIconName isEqualToString:@"custom.photo"]){
        if(gCustomPhotoImage)return [gCustomPhotoImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        return [[UIImage systemImageNamed:@"photo.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    UIImage *image=[UIImage systemImageNamed:gIconName]; if(!image)image=[UIImage systemImageNamed:@"star.fill"];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static CGRect LGTIconFrame(CGRect anchor,CGFloat size,NSInteger position) {
    CGFloat spacing=8,x=CGRectGetMaxX(anchor)+spacing,y=CGRectGetMidY(anchor)-size/2;
    if(position==0){x=CGRectGetMinX(anchor)-size-spacing;y=CGRectGetMidY(anchor)-size/2;}
    else if(position==2){x=CGRectGetMidX(anchor)-size/2;y=CGRectGetMinY(anchor)-size-spacing;}
    else if(position==3){x=CGRectGetMidX(anchor)-size/2;y=CGRectGetMaxY(anchor)+spacing;}
    return CGRectMake(x+gIconOffsetX,y+gIconOffsetY,size,size);
}

static void LGTApplyIcon(UIView *container,UILabel *time,UILabel *date) {
    UIImageView *icon=objc_getAssociatedObject(container,LGTIconAssociationKey);
    if(!gEnabled||!gIconEnabled||!time){[icon removeFromSuperview];objc_setAssociatedObject(container,LGTIconAssociationKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);return;}
    if(!icon){icon=[[UIImageView alloc] initWithFrame:CGRectZero];icon.userInteractionEnabled=NO;[container addSubview:icon];objc_setAssociatedObject(container,LGTIconAssociationKey,icon,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    BOOL custom=[gIconName isEqualToString:@"custom.photo"]&&gCustomPhotoImage;
    icon.image=LGTIconImage(); icon.contentMode=custom?UIViewContentModeScaleAspectFill:UIViewContentModeScaleAspectFit; icon.tintColor=custom?nil:(gIconUIColor?:UIColor.whiteColor);
    icon.layer.shadowOpacity=gShadowEnabled?(float)gShadowOpacity:0;icon.layer.shadowRadius=gShadowRadius;icon.layer.shadowOffset=CGSizeMake(gShadowOffsetX,gShadowOffsetY);icon.layer.shadowColor=(gIconShadowUIColor?:UIColor.blackColor).CGColor;icon.layer.masksToBounds=NO;
    UILabel *anchor=(gAnchorTarget==1&&date)?date:time; CGRect frame=[anchor convertRect:anchor.bounds toView:container]; icon.frame=LGTIconFrame(frame,gIconSize,gIconPosition); [container bringSubviewToFront:icon];
}

static void LGTResetContainerBeforeAppleLayout(UIView *container) {
    UILabel *time=nil,*date=nil;LGTResolveLabels(container,&time,&date);if(time)LGTRestoreBeforeAppleLayout(time);if(date)LGTRestoreBeforeAppleLayout(date);
}

static void LGTApplyFinalGeometry(UIView *container) {
    if(!container||!container.window)return; UILabel *time=nil,*date=nil;LGTResolveLabels(container,&time,&date);if(!time)return;
    if(gEnabled&&gCustomTimeEnabled)LGTApplyFinalPosition(time,gTimeOffsetX,gTimeOffsetY);
    if(date&&gEnabled&&gCustomDateEnabled)LGTApplyFinalPosition(date,gDateOffsetX,gDateOffsetY);
    LGTApplyIcon(container,time,date);
}

static void LGTApplyContainerAfterAppleLayout(UIView *container) {
    if(!container)return;[gKnownContainers addObject:container];UILabel *time=nil,*date=nil;LGTResolveLabels(container,&time,&date);
    if(!time){UIImageView *icon=objc_getAssociatedObject(container,LGTIconAssociationKey);[icon removeFromSuperview];return;}
    LGTCaptureNativeAfterAppleLayout(time);if(date)LGTCaptureNativeAfterAppleLayout(date);
    LGTApplyTimeAppearance(time);if(date)LGTApplyDateAppearance(date);
    // Immediate pass, then a next-runloop pass after any font/attributed-text relayout.
    LGTApplyFinalGeometry(container);
    __weak UIView *weakContainer=container;
    dispatch_async(dispatch_get_main_queue(),^{UIView *strongContainer=weakContainer;if(strongContainer)LGTApplyFinalGeometry(strongContainer);});
}

typedef void(*LGTLayoutIMP)(id,SEL);static LGTLayoutIMP gOriginalLayout=NULL;
static void LGTHookedLayout(id self,SEL _cmd){if([self isKindOfClass:UIView.class])LGTResetContainerBeforeAppleLayout((UIView *)self);if(gOriginalLayout)gOriginalLayout(self,_cmd);if([self isKindOfClass:UIView.class])LGTApplyContainerAfterAppleLayout((UIView *)self);}

static Class LGTResolveContainerClass(void){NSArray<NSString *> *candidates=@[@"SBFLockScreenDateView",@"CSDateView",@"SBFLockScreenDateSubtitleView"];for(NSString *name in candidates){Class cls=NSClassFromString(name);if(cls&&class_getInstanceMethod(cls,@selector(layoutSubviews)))return cls;}return Nil;}

%ctor {
    @autoreleasepool {
        gFontCache=[NSMutableDictionary dictionary];gKnownContainers=[NSHashTable weakObjectsHashTable];LGTLoadPrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,LGTReloadCallback,LGTReloadNotification,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
        Class cls=LGTResolveContainerClass();if(cls)MSHookMessageEx(cls,@selector(layoutSubviews),(IMP)LGTHookedLayout,(IMP *)&gOriginalLayout);
    }
}
