#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <unistd.h>
#import <stdlib.h>

static NSString * const NDControlPath = @"/var/mobile/Library/Preferences/com.nextsolution.nextlog.plist";
static NSString * const NDPreferredManifestPath = @"/var/mobile/Library/Preferences/com.nextsolution.nextdiagnostics.manifest.plist";
static NSString * const NDLogDirectory = @"/var/mobile/Library/Logs/NextSolution";
static NSString * const NDControlNotification = @"com.nextsolution.nextlog/control.changed";

static NSString *NDNormalize(NSString *value) {
    if (![value isKindOfClass:NSString.class] || !value.length) return @"";
    NSMutableString *out = [NSMutableString string];
    NSCharacterSet *allowed = NSCharacterSet.alphanumericCharacterSet;
    NSString *lower = value.lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if ([allowed characterIsMember:c]) [out appendFormat:@"%C", c];
    }
    return out;
}

static NSString *NDResolvedManifestPath(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:NDPreferredManifestPath]) return NDPreferredManifestPath;

    NSArray<NSString *> *fallbacks = @[
        @"/var/jb/Library/Application Support/NextDiagnostics/manifest.plist",
        @"/Library/Application Support/NextDiagnostics/manifest.plist"
    ];
    for (NSString *path in fallbacks) if ([fm fileExistsAtPath:path]) return path;

    Dl_info info = {0};
    if (dladdr((const void *)&NDResolvedManifestPath, &info) && info.dli_fname) {
        NSString *imagePath = [NSString stringWithUTF8String:info.dli_fname];
        NSRange r = [imagePath rangeOfString:@"/Library/MobileSubstrate/DynamicLibraries/" options:NSBackwardsSearch];
        if (r.location != NSNotFound) {
            NSString *prefix = [imagePath substringToIndex:r.location];
            NSString *derived = [prefix stringByAppendingPathComponent:@"Library/Application Support/NextDiagnostics/manifest.plist"];
            if ([fm fileExistsAtPath:derived]) return derived;
        }
    }
    return NDPreferredManifestPath;
}

static NSDictionary *NDControl(void) {
    NSDictionary *value = [NSDictionary dictionaryWithContentsOfFile:NDControlPath];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSDictionary *NDManifest(void) {
    NSDictionary *value = [NSDictionary dictionaryWithContentsOfFile:NDResolvedManifestPath()];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray<NSDictionary *> *NDTweakEntries(void) {
    NSArray *items = NDManifest()[@"tweaks"];
    if (![items isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *valid = [NSMutableArray array];
    for (id item in items) if ([item isKindOfClass:NSDictionary.class]) [valid addObject:item];
    return valid;
}

static NSDictionary *NDActiveEntry(void) {
    NSDictionary *control = NDControl();
    if (![control[@"enabled"] boolValue]) return nil;
    NSString *needle = NDNormalize(control[@"activeTweak"]);
    if (!needle.length) needle = NDNormalize(control[@"displayName"]);
    if (!needle.length) needle = NDNormalize(control[@"packageID"]);
    if (!needle.length) return nil;

    for (NSDictionary *entry in NDTweakEntries()) {
        NSMutableArray<NSString *> *values = [NSMutableArray array];
        for (NSString *key in @[@"slug", @"name", @"packageID"]) {
            NSString *value = entry[key];
            if ([value isKindOfClass:NSString.class] && value.length) [values addObject:value];
        }
        NSArray *aliases = entry[@"aliases"];
        if ([aliases isKindOfClass:NSArray.class]) {
            for (id alias in aliases) if ([alias isKindOfClass:NSString.class]) [values addObject:alias];
        }
        for (NSString *value in values) {
            NSString *n = NDNormalize(value);
            if ([n isEqualToString:needle] || [needle containsString:n] || [n containsString:needle]) return entry;
        }
    }
    return nil;
}

static NSString *NDLogPathForEntry(NSDictionary *entry) {
    NSString *file = entry[@"logFile"];
    if (![file isKindOfClass:NSString.class] || !file.length) {
        NSString *slug = entry[@"slug"];
        file = [NSString stringWithFormat:@"%@.log", ([slug isKindOfClass:NSString.class] && slug.length) ? slug : @"unknown-tweak"];
    }
    return [NDLogDirectory stringByAppendingPathComponent:file];
}

static void NDWrite(NSDictionary *entry, NSString *format, ...) {
    if (!entry || !format.length) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:NDLogDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = NDLogPathForEntry(entry);
    NSString *line = [NSString stringWithFormat:@"[%@] NEXTDIAG %@\n", NSDate.date, message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    @synchronized (NSFileManager.class) {
        if (![fm fileExistsAtPath:path]) {
            [data writeToFile:path atomically:YES];
        } else {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            if (handle) {
                [handle seekToEndOfFile];
                [handle writeData:data];
                [handle closeFile];
            }
        }
    }
}

static NSArray<NSString *> *NDLoadedImageNames(void) {
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *path = [NSString stringWithUTF8String:name];
        if (path.length) [items addObject:path.lastPathComponent ?: path];
    }
    return items;
}

static BOOL NDArrayContainsNormalized(NSArray *array, NSString *needle) {
    if (![array isKindOfClass:NSArray.class] || !needle.length) return NO;
    for (id item in array) {
        if (![item isKindOfClass:NSString.class]) continue;
        NSString *n = NDNormalize(item);
        if ([n isEqualToString:needle]) return YES;
    }
    return NO;
}

static NSArray<NSString *> *NDExpectedLoadedDylibs(NSDictionary *entry, NSArray<NSString *> *loaded) {
    NSArray *expected = entry[@"dylibs"];
    if (![expected isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *hits = [NSMutableArray array];
    for (id dylib in expected) {
        if (![dylib isKindOfClass:NSString.class]) continue;
        NSString *expectedName = [(NSString *)dylib lastPathComponent];
        for (NSString *actual in loaded) {
            if ([actual.lastPathComponent caseInsensitiveCompare:expectedName] == NSOrderedSame) {
                [hits addObject:actual.lastPathComponent];
                break;
            }
        }
    }
    return hits;
}

static BOOL NDProcessMatchesEntry(NSDictionary *entry, NSArray<NSString *> *loaded, NSArray<NSString *> **hitsOut) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    NSString *process = NSProcessInfo.processInfo.processName ?: @"";
    NSString *bundleN = NDNormalize(bundle);
    NSString *processN = NDNormalize(process);

    BOOL bundleMatch = NDArrayContainsNormalized(entry[@"bundles"], bundleN);
    BOOL executableMatch = NDArrayContainsNormalized(entry[@"executables"], processN);
    NSArray<NSString *> *hits = NDExpectedLoadedDylibs(entry, loaded);
    if (hitsOut) *hitsOut = hits;
    return bundleMatch || executableMatch || hits.count > 0;
}

static void NDEmitSnapshot(NSString *reason) {
    NSDictionary *entry = NDActiveEntry();
    if (!entry) return;
    NSArray<NSString *> *loaded = NDLoadedImageNames();
    NSArray<NSString *> *hits = nil;
    if (!NDProcessMatchesEntry(entry, loaded, &hits)) return;

    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"<nil>";
    NSString *process = NSProcessInfo.processInfo.processName ?: @"<nil>";
    NSArray *expected = [entry[@"dylibs"] isKindOfClass:NSArray.class] ? entry[@"dylibs"] : @[];
    NDWrite(entry,
            @"snapshot reason=%@ runtime=1.0.0 process=%@ bundle=%@ pid=%d package=%@ version=%@ manifest=%@ expectedDylibs=%@ loadedMatches=%@ bundles=%@ executables=%@",
            reason ?: @"unknown", process, bundle, getpid(), entry[@"packageID"] ?: @"<nil>",
            entry[@"version"] ?: @"<nil>", NDResolvedManifestPath(), expected, hits ?: @[],
            entry[@"bundles"] ?: @[], entry[@"executables"] ?: @[]);
}

static void NDControlChanged(__unused CFNotificationCenterRef center,
                             __unused void *observer,
                             __unused CFStringRef name,
                             __unused const void *object,
                             __unused CFDictionaryRef userInfo) {
    @autoreleasepool { NDEmitSnapshot(@"nextlog.control"); }
}

static void NDImageAdded(const struct mach_header *mh, intptr_t slide) {
    (void)slide;
    @autoreleasepool {
        NSDictionary *entry = NDActiveEntry();
        if (!entry || !mh) return;
        Dl_info info = {0};
        if (!dladdr((const void *)mh, &info) || !info.dli_fname) return;
        NSString *path = [NSString stringWithUTF8String:info.dli_fname];
        NSString *name = path.lastPathComponent ?: path;
        NSArray *expected = entry[@"dylibs"];
        if (![expected isKindOfClass:NSArray.class]) return;
        for (id item in expected) {
            if (![item isKindOfClass:NSString.class]) continue;
            if ([[(NSString *)item lastPathComponent] caseInsensitiveCompare:name] == NSOrderedSame) {
                NDWrite(entry, @"dyld-loaded process=%@ bundle=%@ pid=%d dylib=%@ path=%@",
                        NSProcessInfo.processInfo.processName ?: @"<nil>",
                        NSBundle.mainBundle.bundleIdentifier ?: @"<nil>", getpid(), name, path);
                break;
            }
        }
    }
}

__attribute__((constructor)) static void NextDiagnosticsRuntimeInit(void) {
    @autoreleasepool {
        // The package may contain separate Bundle and Executable loader copies of
        // this same binary. Only one instance should register in any process.
        if (getenv("NEXTSOLUTION_NEXTDIAG_ACTIVE")) return;
        setenv("NEXTSOLUTION_NEXTDIAG_ACTIVE", "1", 0);

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NDControlChanged,
                                        (__bridge CFStringRef)NDControlNotification, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        _dyld_register_func_for_add_image(NDImageAdded);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NDEmitSnapshot(@"process-load");
        });
    }
}
