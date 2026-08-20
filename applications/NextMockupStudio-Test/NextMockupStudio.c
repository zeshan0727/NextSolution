// Next Mockup Studio — iPhone 17 Pro Max single-device TIPA prototype
// UIKit is called through the Objective-C runtime so this prototype can be cross-linked.

typedef void *id;
typedef void *Class;
typedef void *SEL;
typedef void (*IMP)(void);
typedef unsigned long NSUInteger;
typedef signed char BOOL;
typedef double CGFloat;

typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { CGFloat a,b,c,d,tx,ty; } CGAffineTransform;

extern Class objc_getClass(const char *name);
extern SEL sel_registerName(const char *str);
extern void *objc_msgSend(void);
extern Class objc_allocateClassPair(Class superclass, const char *name, unsigned long extraBytes);
extern void objc_registerClassPair(Class cls);
extern BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types);

extern int UIApplicationMain(int argc, char **argv, id principalClassName, id delegateClassName);
extern void UIGraphicsBeginImageContextWithOptions(CGSize size, BOOL opaque, CGFloat scale);
extern id UIGraphicsGetImageFromCurrentImageContext(void);
extern void UIGraphicsEndImageContext(void);
extern void UIImageWriteToSavedPhotosAlbum(id image, id completionTarget, SEL completionSelector, void *contextInfo);

#define YES ((BOOL)1)
#define NO  ((BOOL)0)
#define UIControlStateNormal 0UL
#define UIControlEventTouchUpInside 64UL
#define UIControlEventValueChanged 4096UL

static id gWindow, gRootVC, gCanvas, gPhone, gScreenshotView, gFrameView, gHintLabel, gStatusLabel, gScaleSlider;
static int gFinish = 0;
static int gBackground = 0;
static CGRect gPhoneBaseFrame;

static SEL S(const char *name) { return sel_registerName(name); }
static id C(const char *name) { return (id)objc_getClass(name); }

static id M0(id o, const char *s) { return ((id(*)(id,SEL))objc_msgSend)(o,S(s)); }
static id M1(id o, const char *s, id a) { return ((id(*)(id,SEL,id))objc_msgSend)(o,S(s),a); }
static void V0(id o, const char *s) { ((void(*)(id,SEL))objc_msgSend)(o,S(s)); }
static void V1(id o, const char *s, id a) { ((void(*)(id,SEL,id))objc_msgSend)(o,S(s),a); }
static void VB(id o, const char *s, BOOL a) { ((void(*)(id,SEL,BOOL))objc_msgSend)(o,S(s),a); }
static void VI(id o, const char *s, long a) { ((void(*)(id,SEL,long))objc_msgSend)(o,S(s),a); }
static void VU(id o, const char *s, NSUInteger a) { ((void(*)(id,SEL,NSUInteger))objc_msgSend)(o,S(s),a); }
static CGRect MR(id o, const char *s) { return ((CGRect(*)(id,SEL))objc_msgSend)(o,S(s)); }
static id MRInit(id o, const char *s, CGRect r) { return ((id(*)(id,SEL,CGRect))objc_msgSend)(o,S(s),r); }
static void VR(id o, const char *s, CGRect r) { ((void(*)(id,SEL,CGRect))objc_msgSend)(o,S(s),r); }
static void VD(id o, const char *s, CGFloat d) { ((void(*)(id,SEL,CGFloat))objc_msgSend)(o,S(s),d); }
static void VF(id o, const char *s, float f) { ((void(*)(id,SEL,float))objc_msgSend)(o,S(s),f); }
static float MF(id o, const char *s) { return ((float(*)(id,SEL))objc_msgSend)(o,S(s)); }
static void VT(id o, const char *s, CGAffineTransform t) { ((void(*)(id,SEL,CGAffineTransform))objc_msgSend)(o,S(s),t); }
static id MColor4(id o, const char *s, CGFloat r, CGFloat g, CGFloat b, CGFloat a) { return ((id(*)(id,SEL,CGFloat,CGFloat,CGFloat,CGFloat))objc_msgSend)(o,S(s),r,g,b,a); }
static void VTitle(id o, const char *s, id title, NSUInteger state) { ((void(*)(id,SEL,id,NSUInteger))objc_msgSend)(o,S(s),title,state); }
static void VTarget(id o, const char *s, id target, SEL action, NSUInteger events) { ((void(*)(id,SEL,id,SEL,NSUInteger))objc_msgSend)(o,S(s),target,action,events); }
static void VPresent(id o, const char *s, id vc, BOOL animated, id completion) { ((void(*)(id,SEL,id,BOOL,id))objc_msgSend)(o,S(s),vc,animated,completion); }
static void VDismiss(id o, const char *s, BOOL animated, id completion) { ((void(*)(id,SEL,BOOL,id))objc_msgSend)(o,S(s),animated,completion); }
static BOOL VDraw(id o, const char *s, CGRect r, BOOL after) { return ((BOOL(*)(id,SEL,CGRect,BOOL))objc_msgSend)(o,S(s),r,after); }

static id Str(const char *utf8) { return ((id(*)(id,SEL,const char*))objc_msgSend)(C("NSString"),S("stringWithUTF8String:"),utf8); }
static CGRect R(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { CGRect r; r.origin.x=x; r.origin.y=y; r.size.width=w; r.size.height=h; return r; }
static id Color(CGFloat r, CGFloat g, CGFloat b, CGFloat a) { return MColor4(C("UIColor"),"colorWithRed:green:blue:alpha:",r,g,b,a); }

static id Font(CGFloat size, BOOL bold) {
    if (bold) return ((id(*)(id,SEL,CGFloat))objc_msgSend)(C("UIFont"),S("boldSystemFontOfSize:"),size);
    return ((id(*)(id,SEL,CGFloat))objc_msgSend)(C("UIFont"),S("systemFontOfSize:"),size);
}

static id NewView(CGRect frame) {
    id v=M0(C("UIView"),"alloc"); return MRInit(v,"initWithFrame:",frame);
}
static id NewLabel(CGRect frame, const char *text, CGFloat size, BOOL bold, id color) {
    id l=M0(C("UILabel"),"alloc"); l=MRInit(l,"initWithFrame:",frame);
    V1(l,"setText:",Str(text)); V1(l,"setFont:",Font(size,bold)); V1(l,"setTextColor:",color);
    return l;
}
static id NewButton(CGRect frame, const char *title, id target, const char *action) {
    id b=((id(*)(id,SEL,long))objc_msgSend)(C("UIButton"),S("buttonWithType:"),1L);
    VR(b,"setFrame:",frame); VTitle(b,"setTitle:forState:",Str(title),UIControlStateNormal);
    V1(b,"setTitleColor:",Color(1,1,1,1)); V1(b,"setBackgroundColor:",Color(0.12,0.13,0.16,0.96));
    id layer=M0(b,"layer"); VD(layer,"setCornerRadius:",12.0); VB(layer,"setMasksToBounds:",YES);
    VTarget(b,"addTarget:action:forControlEvents:",target,S(action),UIControlEventTouchUpInside);
    return b;
}

static void SetStatus(const char *text) { if (gStatusLabel) V1(gStatusLabel,"setText:",Str(text)); }

static const char *FrameAssetName(void) {
    if (gFinish==1) return "iphone17promax_orange.png";
    if (gFinish==2) return "iphone17promax_blue.png";
    return "iphone17promax_silver.png";
}
static void UpdateFrameAsset(void) {
    id img=M1(C("UIImage"),"imageNamed:",Str(FrameAssetName()));
    V1(gFrameView,"setImage:",img);
}

static void SetCanvasBackground(void) {
    if (gBackground==1) V1(gCanvas,"setBackgroundColor:",Color(0.96,0.96,0.98,1));
    else if (gBackground==2) V1(gCanvas,"setBackgroundColor:",Color(0.08,0.18,0.35,1));
    else V1(gCanvas,"setBackgroundColor:",Color(0.035,0.038,0.05,1));
}

static void chooseSilver(id self, SEL _cmd, id sender) { (void)self;(void)_cmd;(void)sender; gFinish=0; UpdateFrameAsset(); SetStatus("Silver finish selected"); }
static void chooseOrange(id self, SEL _cmd, id sender) { (void)self;(void)_cmd;(void)sender; gFinish=1; UpdateFrameAsset(); SetStatus("Cosmic Orange selected"); }
static void chooseBlue(id self, SEL _cmd, id sender) { (void)self;(void)_cmd;(void)sender; gFinish=2; UpdateFrameAsset(); SetStatus("Deep Blue selected"); }
static void cycleBackground(id self, SEL _cmd, id sender) { (void)self;(void)_cmd;(void)sender; gBackground=(gBackground+1)%3; SetCanvasBackground(); SetStatus("Background changed"); }

static void scaleChanged(id self, SEL _cmd, id sender) {
    (void)self;(void)_cmd;
    float value=MF(sender,"value");
    CGAffineTransform t={(CGFloat)value,0,0,(CGFloat)value,0,0};
    VT(gPhone,"setTransform:",t);
}

static void pickScreenshot(id self, SEL _cmd, id sender) {
    (void)_cmd;(void)sender;
    id picker=M0(C("UIImagePickerController"),"alloc"); picker=M0(picker,"init");
    VI(picker,"setSourceType:",0L); V1(picker,"setDelegate:",self); VB(picker,"setAllowsEditing:",NO);
    SetStatus("Choose a screenshot from Photos");
    VPresent(gRootVC,"presentViewController:animated:completion:",picker,YES,(id)0);
}

static void pickerDone(id self, SEL _cmd, id picker, id info) {
    (void)self;(void)_cmd;
    id image=M1(info,"objectForKey:",Str("UIImagePickerControllerOriginalImage"));
    if (image) { V1(gScreenshotView,"setImage:",image); VB(gHintLabel,"setHidden:",YES); SetStatus("Screenshot fitted to iPhone 17 Pro Max"); }
    VDismiss(picker,"dismissViewControllerAnimated:completion:",YES,(id)0);
}

static void pickerCancel(id self, SEL _cmd, id picker) {
    (void)self;(void)_cmd;
    VDismiss(picker,"dismissViewControllerAnimated:completion:",YES,(id)0);
    SetStatus("Import cancelled");
}

static void saveMockup(id self, SEL _cmd, id sender) {
    (void)self;(void)_cmd;(void)sender;
    CGRect b=MR(gCanvas,"bounds");
    UIGraphicsBeginImageContextWithOptions(b.size,NO,3.0);
    VDraw(gCanvas,"drawViewHierarchyInRect:afterScreenUpdates:",b,YES);
    id img=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (img) { UIImageWriteToSavedPhotosAlbum(img,(id)0,(SEL)0,(void*)0); SetStatus("Saved to Photos ✓"); }
    else SetStatus("Export failed");
}

static BOOL appLaunch(id self, SEL _cmd, id app, id options) {
    (void)_cmd;(void)app;(void)options;
    id screen=M0(C("UIScreen"),"mainScreen"); CGRect bounds=MR(screen,"bounds");
    CGFloat W=bounds.size.width, H=bounds.size.height;

    gWindow=M0(C("UIWindow"),"alloc"); gWindow=MRInit(gWindow,"initWithFrame:",bounds);
    gRootVC=M0(C("UIViewController"),"alloc"); gRootVC=M0(gRootVC,"init");
    id root=M0(gRootVC,"view"); V1(root,"setBackgroundColor:",Color(0.012,0.014,0.02,1));

    id title=NewLabel(R(20,50,W-40,36),"Next Mockup Studio",28,YES,Color(1,1,1,1)); V1(root,"addSubview:",title);
    id sub=NewLabel(R(20,87,W-40,23),"iPhone 17 Pro Max • Premium test build",14,NO,Color(0.62,0.66,0.74,1)); V1(root,"addSubview:",sub);

    CGFloat canvasY=124, controlsH=210, canvasH=H-canvasY-controlsH;
    if (canvasH<410) canvasH=410;
    gCanvas=NewView(R(16,canvasY,W-32,canvasH)); SetCanvasBackground();
    id cl=M0(gCanvas,"layer"); VD(cl,"setCornerRadius:",24.0); VB(cl,"setMasksToBounds:",YES);
    V1(root,"addSubview:",gCanvas);

    CGFloat canvasW=W-32;
    CGFloat phoneW=canvasW*0.56; if (phoneW>250) phoneW=250; if (phoneW<190) phoneW=190;
    CGFloat phoneH=phoneW*2.095;
    if (phoneH>canvasH-34) { phoneH=canvasH-34; phoneW=phoneH/2.095; }
    CGFloat px=(canvasW-phoneW)/2.0, py=(canvasH-phoneH)/2.0;
    gPhoneBaseFrame=R(px,py,phoneW,phoneH);
    gPhone=NewView(gPhoneBaseFrame); V1(gPhone,"setBackgroundColor:",Color(0,0,0,0));
    V1(gCanvas,"addSubview:",gPhone);

    CGFloat sx=phoneW*(109.0/3000.0), sy=phoneH*(120.0/6285.0);
    CGFloat sw=phoneW*(2782.0/3000.0), sh=phoneH*(6045.0/6285.0);
    gScreenshotView=M0(C("UIImageView"),"alloc"); gScreenshotView=MRInit(gScreenshotView,"initWithFrame:",R(sx,sy,sw,sh));
    V1(gScreenshotView,"setBackgroundColor:",Color(0.025,0.028,0.04,1)); VI(gScreenshotView,"setContentMode:",2L); VB(gScreenshotView,"setClipsToBounds:",YES);
    id sl=M0(gScreenshotView,"layer"); VD(sl,"setCornerRadius:",phoneW*(190.0/3000.0)); VB(sl,"setMasksToBounds:",YES);
    V1(gPhone,"addSubview:",gScreenshotView);

    gHintLabel=NewLabel(R(sx+10,sy+sh*0.42,sw-20,50),"IMPORT\nSCREENSHOT",13,YES,Color(0.7,0.74,0.82,1));
    VI(gHintLabel,"setTextAlignment:",1L); VI(gHintLabel,"setNumberOfLines:",2L); V1(gPhone,"addSubview:",gHintLabel);

    gFrameView=M0(C("UIImageView"),"alloc"); gFrameView=MRInit(gFrameView,"initWithFrame:",R(0,0,phoneW,phoneH));
    VI(gFrameView,"setContentMode:",1L); VB(gFrameView,"setUserInteractionEnabled:",NO); UpdateFrameAsset(); V1(gPhone,"addSubview:",gFrameView);

    CGFloat controlsY=canvasY+canvasH+14;
    CGFloat half=(W-52)/2.0;
    id importB=NewButton(R(16,controlsY,half,46),"Import Screenshot",self,"pickScreenshot:"); V1(root,"addSubview:",importB);
    id saveB=NewButton(R(36+half,controlsY,half,46),"Save PNG",self,"saveMockup:"); V1(root,"addSubview:",saveB);

    CGFloat third=(W-56)/3.0; CGFloat y2=controlsY+56;
    id sB=NewButton(R(16,y2,third,42),"Silver",self,"chooseSilver:"); V1(root,"addSubview:",sB);
    id oB=NewButton(R(20+third,y2,third,42),"Orange",self,"chooseOrange:"); V1(root,"addSubview:",oB);
    id bB=NewButton(R(24+third*2,y2,third,42),"Deep Blue",self,"chooseBlue:"); V1(root,"addSubview:",bB);

    CGFloat y3=y2+51;
    id bgB=NewButton(R(16,y3,112,38),"Background",self,"cycleBackground:"); V1(root,"addSubview:",bgB);
    gScaleSlider=M0(C("UISlider"),"alloc"); gScaleSlider=MRInit(gScaleSlider,"initWithFrame:",R(142,y3,W-158,38));
    VF(gScaleSlider,"setMinimumValue:",0.72f); VF(gScaleSlider,"setMaximumValue:",1.08f);
    ((void(*)(id,SEL,float,BOOL))objc_msgSend)(gScaleSlider,S("setValue:animated:"),0.92f,NO);
    VTarget(gScaleSlider,"addTarget:action:forControlEvents:",self,S("scaleChanged:"),UIControlEventValueChanged); V1(root,"addSubview:",gScaleSlider);

    gStatusLabel=NewLabel(R(18,y3+42,W-36,28),"Ready • iPhone 17 Pro Max • 2868 × 1320",12,NO,Color(0.55,0.6,0.7,1));
    VI(gStatusLabel,"setTextAlignment:",1L); V1(root,"addSubview:",gStatusLabel);

    V1(gWindow,"setRootViewController:",gRootVC); V0(gWindow,"makeKeyAndVisible");
    return YES;
}

int main(int argc, char **argv) {
    Class ns=objc_getClass("NSObject");
    Class delegate=objc_allocateClassPair(ns,"NMAppDelegate",0);
    class_addMethod(delegate,S("application:didFinishLaunchingWithOptions:"),(IMP)appLaunch,"B@:@@");
    class_addMethod(delegate,S("pickScreenshot:"),(IMP)pickScreenshot,"v@:@");
    class_addMethod(delegate,S("saveMockup:"),(IMP)saveMockup,"v@:@");
    class_addMethod(delegate,S("chooseSilver:"),(IMP)chooseSilver,"v@:@");
    class_addMethod(delegate,S("chooseOrange:"),(IMP)chooseOrange,"v@:@");
    class_addMethod(delegate,S("chooseBlue:"),(IMP)chooseBlue,"v@:@");
    class_addMethod(delegate,S("cycleBackground:"),(IMP)cycleBackground,"v@:@");
    class_addMethod(delegate,S("scaleChanged:"),(IMP)scaleChanged,"v@:@");
    class_addMethod(delegate,S("imagePickerController:didFinishPickingMediaWithInfo:"),(IMP)pickerDone,"v@:@@");
    class_addMethod(delegate,S("imagePickerControllerDidCancel:"),(IMP)pickerCancel,"v@:@");
    objc_registerClassPair(delegate);
    return UIApplicationMain(argc,argv,(id)0,Str("NMAppDelegate"));
}
