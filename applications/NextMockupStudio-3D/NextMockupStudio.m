#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>

@interface NMAppDelegate : UIResponder <UIApplicationDelegate,UIImagePickerControllerDelegate,UINavigationControllerDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIViewController *vc;
@property(nonatomic,strong) SCNView *sceneView;
@property(nonatomic,strong) SCNNode *phoneRoot;
@property(nonatomic,strong) SCNMaterial *bodyMat,*buttonMat,*screenMat,*glassMat;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIButton *clearButton;
@property(nonatomic) NSInteger finish;
@property(nonatomic) BOOL clearExport;
@end

@implementation NMAppDelegate

- (UIColor*)c:(CGFloat)r g:(CGFloat)g b:(CGFloat)b a:(CGFloat)a { return [UIColor colorWithRed:r green:g blue:b alpha:a]; }
- (UILabel*)label:(CGRect)f text:(NSString*)t size:(CGFloat)s bold:(BOOL)b color:(UIColor*)c { UILabel*l=[[UILabel alloc]initWithFrame:f]; l.text=t; l.font=b?[UIFont boldSystemFontOfSize:s]:[UIFont systemFontOfSize:s]; l.textColor=c; return l; }
- (UIButton*)button:(CGRect)f title:(NSString*)t action:(SEL)a { UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem]; b.frame=f; [b setTitle:t forState:UIControlStateNormal]; [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; b.backgroundColor=[self c:.12 g:.13 b:.16 a:.96]; b.layer.cornerRadius=12; b.clipsToBounds=YES; [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside]; return b; }

- (void)setStatus:(NSString*)s { self.status.text=s; }
- (void)applyFinish { UIColor*body,*btn; if(self.finish==1){body=[self c:.86 g:.44 b:.22 a:1];btn=[self c:.56 g:.24 b:.10 a:1];} else if(self.finish==2){body=[self c:.33 g:.46 b:.61 a:1];btn=[self c:.15 g:.23 b:.33 a:1];} else {body=[self c:.81 g:.83 b:.86 a:1];btn=[self c:.63 g:.66 b:.70 a:1];} self.bodyMat.diffuse.contents=body; self.bodyMat.specular.contents=UIColor.whiteColor; self.buttonMat.diffuse.contents=btn; self.glassMat.diffuse.contents=[self c:.06 g:.06 b:.08 a:1]; self.glassMat.specular.contents=[self c:1 g:1 b:1 a:.55]; }

- (SCNNode*)nodeForBoxW:(CGFloat)w h:(CGFloat)h l:(CGFloat)l r:(CGFloat)r color:(UIColor*)color pos:(SCNVector3)p materialOut:(SCNMaterial**)out { SCNBox*g=[SCNBox boxWithWidth:w height:h length:l chamferRadius:r]; g.firstMaterial.diffuse.contents=color; if(out)*out=g.firstMaterial; SCNNode*n=[SCNNode nodeWithGeometry:g]; n.position=p; return n; }

- (SCNScene*)makeScene {
    SCNScene*s=[SCNScene scene];
    SCNNode*cam=[SCNNode node]; cam.camera=[SCNCamera camera]; cam.position=SCNVector3Make(0,0,220); [s.rootNode addChildNode:cam];
    self.phoneRoot=[SCNNode node]; self.phoneRoot.eulerAngles=SCNVector3Make(.18,-.38,0); [s.rootNode addChildNode:self.phoneRoot];

    [self.phoneRoot addChildNode:[self nodeForBoxW:74 h:154 l:8.2 r:9.5 color:[self c:.81 g:.83 b:.86 a:1] pos:SCNVector3Zero materialOut:&_bodyMat]];
    [self.phoneRoot addChildNode:[self nodeForBoxW:69.4 h:149 l:.9 r:7.2 color:[self c:.06 g:.06 b:.08 a:1] pos:SCNVector3Make(0,0,4.1) materialOut:&_glassMat]];
    SCNNode*screen=[self nodeForBoxW:66.5 h:144 l:.3 r:6.8 color:[self c:.10 g:.22 b:.36 a:1] pos:SCNVector3Make(0,-1,4.75) materialOut:&_screenMat]; [self.phoneRoot addChildNode:screen];
    [self.phoneRoot addChildNode:[self nodeForBoxW:18 h:5 l:.45 r:2.5 color:[self c:.01 g:.01 b:.02 a:1] pos:SCNVector3Make(0,67,4.95) materialOut:NULL]];
    [self.phoneRoot addChildNode:[self nodeForBoxW:8.5 h:1.2 l:.2 r:.4 color:[self c:.10 g:.10 b:.10 a:1] pos:SCNVector3Make(0,73,5) materialOut:NULL]];

    SCNNode*v1=[self nodeForBoxW:1.4 h:18 l:1.2 r:.6 color:[self c:.63 g:.66 b:.70 a:1] pos:SCNVector3Make(-37.2,24,0) materialOut:&_buttonMat]; [self.phoneRoot addChildNode:v1];
    [self.phoneRoot addChildNode:[self nodeForBoxW:1.4 h:18 l:1.2 r:.6 color:[self c:.63 g:.66 b:.70 a:1] pos:SCNVector3Make(-37.2,-1,0) materialOut:NULL]];
    [self.phoneRoot addChildNode:[self nodeForBoxW:1.4 h:8 l:1.2 r:.6 color:[self c:.63 g:.66 b:.70 a:1] pos:SCNVector3Make(-37.2,48,0) materialOut:NULL]];
    [self.phoneRoot addChildNode:[self nodeForBoxW:1.4 h:28 l:1.2 r:.6 color:[self c:.63 g:.66 b:.70 a:1] pos:SCNVector3Make(37.2,12,0) materialOut:NULL]];

    SCNPlane*shadow=[SCNPlane planeWithWidth:130 height:220]; shadow.firstMaterial.diffuse.contents=[self c:0 g:0 b:0 a:.12]; SCNNode*sn=[SCNNode nodeWithGeometry:shadow]; sn.position=SCNVector3Make(0,-88,-20); sn.eulerAngles=SCNVector3Make(-M_PI_2,0,0); [s.rootNode addChildNode:sn];
    [self applyFinish]; return s;
}

- (BOOL)application:(UIApplication*)app didFinishLaunchingWithOptions:(NSDictionary*)opts { (void)app;(void)opts; CGRect b=UIScreen.mainScreen.bounds; CGFloat W=b.size.width,H=b.size.height; self.window=[[UIWindow alloc]initWithFrame:b]; self.vc=[UIViewController new]; UIView*root=self.vc.view; root.backgroundColor=[self c:.012 g:.014 b:.02 a:1];
    [root addSubview:[self label:CGRectMake(20,50,W-40,36) text:@"Next Mockup Studio" size:28 bold:YES color:UIColor.whiteColor]];
    [root addSubview:[self label:CGRectMake(20,88,W-40,22) text:@"Live 3D iPhone proof build" size:14 bold:NO color:[self c:.65 g:.68 b:.75 a:1]]];
    [root addSubview:[self label:CGRectMake(20,108,W-40,18) text:@"Drag to rotate • pinch to zoom • screenshot becomes screen texture" size:11 bold:NO color:[self c:.50 g:.56 b:.66 a:1]]];
    CGFloat sy=132,ch=H-sy-170; if(ch<360)ch=360; UIView*holder=[[UIView alloc]initWithFrame:CGRectMake(16,sy,W-32,ch)]; holder.backgroundColor=[self c:.03 g:.035 b:.05 a:1]; holder.layer.cornerRadius=24; holder.clipsToBounds=YES; [root addSubview:holder];
    self.sceneView=[[SCNView alloc]initWithFrame:holder.bounds]; self.sceneView.scene=[self makeScene]; self.sceneView.allowsCameraControl=YES; self.sceneView.autoenablesDefaultLighting=YES; self.sceneView.jitteringEnabled=YES; self.sceneView.backgroundColor=[self c:.03 g:.035 b:.05 a:1]; [holder addSubview:self.sceneView];
    CGFloat y1=sy+ch+12, half=(W-52)/2; [root addSubview:[self button:CGRectMake(16,y1,half,42) title:@"Import Screenshot" action:@selector(pickScreenshot:)]]; [root addSubview:[self button:CGRectMake(36+half,y1,half,42) title:@"Save PNG" action:@selector(save:)]];
    CGFloat third=(W-56)/3,y2=y1+50; [root addSubview:[self button:CGRectMake(16,y2,third,38) title:@"Silver" action:@selector(silver:)]]; [root addSubview:[self button:CGRectMake(20+third,y2,third,38) title:@"Orange" action:@selector(orange:)]]; [root addSubview:[self button:CGRectMake(24+third*2,y2,third,38) title:@"Deep Blue" action:@selector(blue:)]];
    CGFloat y3=y2+46; self.clearButton=[self button:CGRectMake(16,y3,140,36) title:@"Clear PNG OFF" action:@selector(toggleClear:)]; [root addSubview:self.clearButton]; self.status=[self label:CGRectMake(166,y3+8,W-182,20) text:@"Ready • live 3D phone" size:12 bold:NO color:[self c:.56 g:.62 b:.72 a:1]]; [root addSubview:self.status];
    self.window.rootViewController=self.vc; [self.window makeKeyAndVisible]; return YES; }

- (void)silver:(id)s { (void)s; self.finish=0; [self applyFinish]; [self setStatus:@"Finish: Silver"]; }
- (void)orange:(id)s { (void)s; self.finish=1; [self applyFinish]; [self setStatus:@"Finish: Cosmic Orange"]; }
- (void)blue:(id)s { (void)s; self.finish=2; [self applyFinish]; [self setStatus:@"Finish: Deep Blue"]; }
- (void)toggleClear:(id)s { (void)s; self.clearExport=!self.clearExport; [self.clearButton setTitle:self.clearExport?@"Clear PNG ON":@"Clear PNG OFF" forState:UIControlStateNormal]; [self setStatus:self.clearExport?@"Transparent export enabled":@"Transparent export disabled"]; }
- (void)pickScreenshot:(id)s { (void)s; UIImagePickerController*p=[UIImagePickerController new]; p.sourceType=UIImagePickerControllerSourceTypePhotoLibrary; p.delegate=self; [self.vc presentViewController:p animated:YES completion:nil]; }
- (void)imagePickerController:(UIImagePickerController*)p didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id>*)info { UIImage*i=info[UIImagePickerControllerOriginalImage]; if(i){ self.screenMat.diffuse.contents=i; self.screenMat.diffuse.contentsTransform=SCNMatrix4MakeScale(1,-1,1); self.screenMat.diffuse.wrapS=SCNWrapModeClamp; self.screenMat.diffuse.wrapT=SCNWrapModeClamp; [self setStatus:@"Screenshot applied to 3D screen"]; } [p dismissViewControllerAnimated:YES completion:nil]; }
- (void)imagePickerControllerDidCancel:(UIImagePickerController*)p { [p dismissViewControllerAnimated:YES completion:nil]; }
- (void)save:(id)s { (void)s; UIColor*old=self.sceneView.backgroundColor; BOOL oldOpaque=self.sceneView.opaque; if(self.clearExport){ self.sceneView.backgroundColor=UIColor.clearColor; self.sceneView.opaque=NO; } UIGraphicsBeginImageContextWithOptions(self.sceneView.bounds.size,NO,3); [self.sceneView drawViewHierarchyInRect:self.sceneView.bounds afterScreenUpdates:YES]; UIImage*i=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); self.sceneView.backgroundColor=old; self.sceneView.opaque=oldOpaque; if(i){ UIImageWriteToSavedPhotosAlbum(i,nil,NULL,NULL); [self setStatus:self.clearExport?@"Transparent PNG saved ✓":@"PNG saved ✓"]; } }
@end

int main(int argc,char*argv[]){ @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass([NMAppDelegate class])); } }
