#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

static NSString * const NDVMDirectoryName = @"NextDroid Android 11.utm";
static NSString * const NDISOName = @"BlissOS-Android11.iso";
static NSString * const NDDataDiskName = @"android-data.img";
static NSString * const NDDownloadURL = @"https://downloads.sourceforge.net/project/blissos-x86/Official/BlissOS14/OpenGApps/Generic/Bliss-v14.10.3-x86_64-OFFICIAL-opengapps-20241012.iso";
static NSString * const NDExpectedSHA256 = @"9feb9482e6e5c41c52172a0d42a436ea808de1cfdd6b1e0187dc883b2df9085c";
static const unsigned long long NDExpectedSize = 2087714816ULL;

@interface NDAndroidInstaller : NSObject <NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, strong) UIViewController *progressController;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *detailLabel;
@end

static NDAndroidInstaller *NDSharedInstaller;

@implementation NDAndroidInstaller

+ (instancetype)sharedInstaller {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NDSharedInstaller = [[self alloc] init];
    });
    return NDSharedInstaller;
}

- (NSURL *)documentsURL {
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                   inDomains:NSUserDomainMask] firstObject];
}

- (NSURL *)virtualMachineURL {
    return [[self documentsURL] URLByAppendingPathComponent:NDVMDirectoryName isDirectory:YES];
}

- (NSURL *)dataDirectoryURL {
    return [[self virtualMachineURL] URLByAppendingPathComponent:@"Data" isDirectory:YES];
}

- (BOOL)isInstalled {
    NSURL *configURL = [[self virtualMachineURL] URLByAppendingPathComponent:@"config.plist"];
    NSURL *isoURL = [[self dataDirectoryURL] URLByAppendingPathComponent:NDISOName];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:isoURL.path error:nil];
    return [[NSFileManager defaultManager] fileExistsAtPath:configURL.path] &&
           [attributes[NSFileSize] unsignedLongLongValue] == NDExpectedSize;
}

- (UIViewController *)topViewController {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateUnattached &&
            [scene isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                    break;
                }
            }
        }
        if (window) {
            break;
        }
    }
    if (!window) {
        window = UIApplication.sharedApplication.windows.firstObject;
    }
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        controller = ((UINavigationController *)controller).visibleViewController;
    } else if ([controller isKindOfClass:UITabBarController.class]) {
        controller = ((UITabBarController *)controller).selectedViewController;
    }
    return controller;
}

- (void)offerInstallation {
    if ([self isInstalled] || self.task) {
        return;
    }
    UIViewController *presenter = [self topViewController];
    if (!presenter || presenter.presentedViewController) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self offerInstallation];
        });
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Install Android 11"
                         message:@"NextDroid needs a one-time 2.0 GB Android download. Keep the app open until verification finishes. Android data remains saved after installation."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Not Now"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Download"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [weakSelf beginDownload];
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)beginDownload {
    [self showProgressController];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
    configuration.timeoutIntervalForRequest = 120.0;
    configuration.timeoutIntervalForResource = 7200.0;
    configuration.allowsCellularAccess = YES;
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;
    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:queue];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:NDDownloadURL]
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:120.0];
    self.task = [self.session downloadTaskWithRequest:request];
    [self.task resume];
}

- (void)showProgressController {
    UIViewController *controller = [[UIViewController alloc] init];
    controller.modalPresentationStyle = UIModalPresentationFormSheet;
    controller.preferredContentSize = CGSizeMake(360.0, 230.0);
    controller.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Preparing Android 11";
    title.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *status = [[UILabel alloc] init];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.text = @"Starting download…";
    status.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    status.textAlignment = NSTextAlignmentCenter;

    UIProgressView *progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progress.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *detail = [[UILabel alloc] init];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.text = @"0 MB of 1,991 MB";
    detail.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    detail.textColor = UIColor.secondaryLabelColor;
    detail.textAlignment = NSTextAlignmentCenter;
    detail.numberOfLines = 2;

    [controller.view addSubview:title];
    [controller.view addSubview:status];
    [controller.view addSubview:progress];
    [controller.view addSubview:detail];
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor constant:28.0],
        [title.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor constant:22.0],
        [title.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor constant:-22.0],
        [status.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:28.0],
        [status.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [status.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [progress.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:22.0],
        [progress.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor constant:32.0],
        [progress.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor constant:-32.0],
        [detail.topAnchor constraintEqualToAnchor:progress.bottomAnchor constant:18.0],
        [detail.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [detail.trailingAnchor constraintEqualToAnchor:title.trailingAnchor]
    ]];

    self.progressController = controller;
    self.statusLabel = status;
    self.progressView = progress;
    self.detailLabel = detail;
    [[self topViewController] presentViewController:controller animated:YES completion:nil];
}

- (NSDictionary *)virtualMachineConfiguration {
    return @{
        @"Backend": @"QEMU",
        @"ConfigurationVersion": @4,
        @"Display": @[@{
            @"DownscalingFilter": @"Linear",
            @"DynamicResolution": @NO,
            @"Hardware": @"virtio-vga",
            @"NativeResolution": @NO,
            @"UpscalingFilter": @"Nearest"
        }],
        @"Drive": @[
            @{
                @"Identifier": @"android-data",
                @"ImageName": NDDataDiskName,
                @"ImageType": @"Disk",
                @"Interface": @"VirtIO",
                @"InterfaceVersion": @1,
                @"ReadOnly": @NO
            },
            @{
                @"Identifier": @"android-installer",
                @"ImageName": NDISOName,
                @"ImageType": @"CD",
                @"Interface": @"IDE",
                @"InterfaceVersion": @1,
                @"ReadOnly": @YES
            }
        ],
        @"Information": @{
            @"Icon": @"android",
            @"IconCustom": @NO,
            @"Name": @"NextDroid Android 11",
            @"Notes": @"Test 1: Bliss OS 14.10.3 (Android 11) with OpenGApps. Install to the Android data disk for persistence.",
            @"UUID": @"E76B434D-3C88-42E7-9E7A-1A82FC876D31"
        },
        @"Input": @{
            @"MaximumUsbShare": @2,
            @"UsbBusSupport": @"3.0",
            @"UsbSharing": @YES
        },
        @"Network": @[@{
            @"Hardware": @"virtio-net-pci",
            @"IsolateFromHost": @NO,
            @"MacAddress": @"52:54:00:11:14:01",
            @"Mode": @"Emulated",
            @"PortForward": @[]
        }],
        @"QEMU": @{
            @"AdditionalArguments": @[],
            @"BalloonDevice": @NO,
            @"DebugLog": @YES,
            @"Hypervisor": @NO,
            @"PS2Controller": @YES,
            @"RNGDevice": @YES,
            @"RTCLocalTime": @NO,
            @"TPMDevice": @NO,
            @"TSO": @NO,
            @"UEFIBoot": @YES
        },
        @"Serial": @[],
        @"Sharing": @{
            @"ClipboardSharing": @NO,
            @"DirectoryShareMode": @"None",
            @"DirectoryShareReadOnly": @NO
        },
        @"Sound": @[@{@"Hardware": @"AC97"}],
        @"System": @{
            @"Architecture": @"x86_64",
            @"CPU": @"default",
            @"CPUCount": @2,
            @"CPUFlagsAdd": @[],
            @"CPUFlagsRemove": @[],
            @"ForceMulticore": @NO,
            @"JITCacheSize": @1024,
            @"MemorySize": @2048,
            @"Target": @"q35"
        }
    };
}

- (NSString *)sha256ForFileAtURL:(NSURL *)url error:(NSError **)error {
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    [stream open];
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    uint8_t buffer[1024 * 1024];
    while (true) {
        NSInteger count = [stream read:buffer maxLength:sizeof(buffer)];
        if (count < 0) {
            if (error) {
                *error = stream.streamError;
            }
            [stream close];
            return nil;
        }
        if (count == 0) {
            break;
        }
        CC_SHA256_Update(&context, buffer, (CC_LONG)count);
    }
    [stream close];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
}

- (BOOL)installDownloadedISOAtURL:(NSURL *)temporaryURL error:(NSError **)error {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:temporaryURL.path error:error];
    if (!attributes || [attributes[NSFileSize] unsignedLongLongValue] != NDExpectedSize) {
        if (error) {
            *error = [NSError errorWithDomain:@"NextDroidInstaller"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"The Android download has an unexpected file size."}];
        }
        return NO;
    }
    NSString *digest = [self sha256ForFileAtURL:temporaryURL error:error];
    if (!digest || ![digest isEqualToString:NDExpectedSHA256]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"NextDroidInstaller"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"Android image verification failed."}];
        }
        return NO;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *vmURL = [self virtualMachineURL];
    NSURL *dataURL = [self dataDirectoryURL];
    [fileManager removeItemAtURL:vmURL error:nil];
    if (![fileManager createDirectoryAtURL:dataURL withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    NSURL *isoURL = [dataURL URLByAppendingPathComponent:NDISOName];
    if (![fileManager moveItemAtURL:temporaryURL toURL:isoURL error:error]) {
        return NO;
    }

    NSURL *diskURL = [dataURL URLByAppendingPathComponent:NDDataDiskName];
    if (![fileManager createFileAtPath:diskURL.path contents:nil attributes:nil]) {
        if (error) {
            *error = [NSError errorWithDomain:@"NextDroidInstaller"
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not create the Android data disk."}];
        }
        return NO;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:diskURL.path];
    @try {
        [handle truncateFileAtOffset:16ULL * 1024ULL * 1024ULL * 1024ULL];
        [handle closeFile];
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"NextDroidInstaller"
                                         code:1004
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Could not size the Android data disk."}];
        }
        return NO;
    }

    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:[self virtualMachineConfiguration]
                                                                    format:NSPropertyListXMLFormat_v1_0
                                                                   options:0
                                                                     error:error];
    if (!plistData) {
        return NO;
    }
    return [plistData writeToURL:[vmURL URLByAppendingPathComponent:@"config.plist"]
                         options:NSDataWritingAtomic
                           error:error];
}

- (void)showResultWithTitle:(NSString *)title message:(NSString *)message success:(BOOL)success {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressController dismissViewControllerAnimated:YES completion:^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                           message:message
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[self topViewController] presentViewController:alert animated:YES completion:nil];
        }];
        if (!success) {
            self.task = nil;
            [self.session invalidateAndCancel];
            self.session = nil;
        }
    });
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    int64_t expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (int64_t)NDExpectedSize;
    float progress = expected > 0 ? (float)((double)totalBytesWritten / (double)expected) : 0.0f;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressView setProgress:progress animated:YES];
        self.statusLabel.text = [NSString stringWithFormat:@"Downloading… %.0f%%", progress * 100.0f];
        self.detailLabel.text = [NSString stringWithFormat:@"%.0f MB of %.0f MB\nKeep NextDroid open",
                                 totalBytesWritten / 1048576.0,
                                 expected / 1048576.0];
    });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = @"Verifying Android image…";
        self.detailLabel.text = @"Checking SHA-256 integrity";
        [self.progressView setProgress:1.0f animated:YES];
    });
    NSError *error = nil;
    BOOL success = [self installDownloadedISOAtURL:location error:&error];
    self.task = nil;
    [self.session finishTasksAndInvalidate];
    self.session = nil;
    if (success) {
        [self showResultWithTitle:@"Android 11 Ready"
                         message:@"Close NextDroid from the app switcher and open it again. Tap “NextDroid Android 11” to start the first boot."
                         success:YES];
    } else {
        [self showResultWithTitle:@"Installation Failed"
                         message:error.localizedDescription ?: @"The Android image could not be installed."
                         success:NO];
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (!error || task != self.task) {
        return;
    }
    [self showResultWithTitle:@"Download Failed"
                     message:error.localizedDescription ?: @"Please check your connection and try again."
                     success:NO];
}

@end

__attribute__((constructor))
static void NDInstallBootstrap(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[NDAndroidInstaller sharedInstaller] offerInstallation];
        });
    });
}
