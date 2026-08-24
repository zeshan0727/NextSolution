#import "NMBPersistentWebsiteDataStore.h"

// These selectors are WebKit compatibility SPI. They are invoked dynamically
// so the app can continue to launch if a future WebKit build removes one.
@interface NSObject (NMBWebsiteDataStoreConfiguration)
- (void)_setWebStorageDirectory:(NSURL *)directory;
- (void)_setIndexedDBDatabaseDirectory:(NSURL *)directory;
- (void)_setWebSQLDatabaseDirectory:(NSURL *)directory;
- (void)_setCookieStorageFile:(NSURL *)file;
- (void)_setResourceLoadStatisticsDirectory:(NSURL *)directory;
- (void)_setCacheStorageDirectory:(NSURL *)directory;
- (void)_setServiceWorkerRegistrationDirectory:(NSURL *)directory;
- (void)setNetworkCacheDirectory:(NSURL *)directory;
- (void)setDeviceIdHashSaltsStorageDirectory:(NSURL *)directory;
- (void)setApplicationCacheDirectory:(NSURL *)directory;
- (void)setMediaCacheDirectory:(NSURL *)directory;
- (void)setMediaKeysStorageDirectory:(NSURL *)directory;
- (void)setHSTSStorageDirectory:(NSURL *)directory;
- (void)setAlternativeServicesStorageDirectory:(NSURL *)directory;
- (void)setGeneralStorageDirectory:(NSURL *)directory;
@end

@interface WKWebsiteDataStore (NMBWebsiteDataStoreConfiguration)
- (instancetype)_initWithConfiguration:(id)configuration;
@end

static NSURL *NMBDirectory(NSURL *rootDirectory, NSString *name)
{
    return [rootDirectory URLByAppendingPathComponent:name isDirectory:YES];
}

static BOOL NMBCreateDirectory(NSFileManager *fileManager, NSURL *directory)
{
    NSError *error = nil;
    BOOL created = [fileManager createDirectoryAtURL:directory
                          withIntermediateDirectories:YES
                                           attributes:@{
                                               NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication
                                           }
                                                error:&error];
    if (!created) {
        NSLog(@"Next Multi Browser could not create profile storage at %@: %@", directory.path, error);
    }
    return created;
}

static void NMBSetURLIfSupported(id configuration, NSString *selectorName, NSURL *URL)
{
    SEL selector = NSSelectorFromString(selectorName);
    if (![configuration respondsToSelector:selector]) {
        return;
    }

    IMP implementation = [configuration methodForSelector:selector];
    void (*setter)(id, SEL, NSURL *) = (void *)implementation;
    setter(configuration, selector, URL);
}

WKWebsiteDataStore *NMBCreatePersistentWebsiteDataStore(NSURL *rootDirectory)
{
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if (!NMBCreateDirectory(fileManager, rootDirectory)) {
        return nil;
    }

    Class configurationClass = NSClassFromString(@"_WKWebsiteDataStoreConfiguration");
    if (!configurationClass) {
        return nil;
    }

    id configuration = [[configurationClass alloc] init];
    if (!configuration) {
        return nil;
    }

    NSURL *cookiesDirectory = NMBDirectory(rootDirectory, @"Cookies");
    NSArray<NSURL *> *directories = @[
        cookiesDirectory,
        NMBDirectory(rootDirectory, @"LocalStorage"),
        NMBDirectory(rootDirectory, @"IndexedDB"),
        NMBDirectory(rootDirectory, @"WebSQL"),
        NMBDirectory(rootDirectory, @"ResourceLoadStatistics"),
        NMBDirectory(rootDirectory, @"CacheStorage"),
        NMBDirectory(rootDirectory, @"ServiceWorkers"),
        NMBDirectory(rootDirectory, @"NetworkCache"),
        NMBDirectory(rootDirectory, @"DeviceIdentifiers"),
        NMBDirectory(rootDirectory, @"ApplicationCache"),
        NMBDirectory(rootDirectory, @"MediaCache"),
        NMBDirectory(rootDirectory, @"MediaKeys"),
        NMBDirectory(rootDirectory, @"HSTS"),
        NMBDirectory(rootDirectory, @"AlternativeServices"),
        NMBDirectory(rootDirectory, @"GeneralStorage")
    ];
    for (NSURL *directory in directories) {
        if (!NMBCreateDirectory(fileManager, directory)) {
            return nil;
        }
    }

    NMBSetURLIfSupported(configuration, @"_setWebStorageDirectory:", NMBDirectory(rootDirectory, @"LocalStorage"));
    NMBSetURLIfSupported(configuration, @"_setIndexedDBDatabaseDirectory:", NMBDirectory(rootDirectory, @"IndexedDB"));
    NMBSetURLIfSupported(configuration, @"_setWebSQLDatabaseDirectory:", NMBDirectory(rootDirectory, @"WebSQL"));
    NMBSetURLIfSupported(configuration, @"_setCookieStorageFile:", [cookiesDirectory URLByAppendingPathComponent:@"Cookies.binarycookies"]);
    NMBSetURLIfSupported(configuration, @"_setResourceLoadStatisticsDirectory:", NMBDirectory(rootDirectory, @"ResourceLoadStatistics"));
    NMBSetURLIfSupported(configuration, @"_setCacheStorageDirectory:", NMBDirectory(rootDirectory, @"CacheStorage"));
    NMBSetURLIfSupported(configuration, @"_setServiceWorkerRegistrationDirectory:", NMBDirectory(rootDirectory, @"ServiceWorkers"));
    NMBSetURLIfSupported(configuration, @"setNetworkCacheDirectory:", NMBDirectory(rootDirectory, @"NetworkCache"));
    NMBSetURLIfSupported(configuration, @"setDeviceIdHashSaltsStorageDirectory:", NMBDirectory(rootDirectory, @"DeviceIdentifiers"));
    NMBSetURLIfSupported(configuration, @"setApplicationCacheDirectory:", NMBDirectory(rootDirectory, @"ApplicationCache"));
    NMBSetURLIfSupported(configuration, @"setMediaCacheDirectory:", NMBDirectory(rootDirectory, @"MediaCache"));
    NMBSetURLIfSupported(configuration, @"setMediaKeysStorageDirectory:", NMBDirectory(rootDirectory, @"MediaKeys"));
    NMBSetURLIfSupported(configuration, @"setHSTSStorageDirectory:", NMBDirectory(rootDirectory, @"HSTS"));
    NMBSetURLIfSupported(configuration, @"setAlternativeServicesStorageDirectory:", NMBDirectory(rootDirectory, @"AlternativeServices"));
    NMBSetURLIfSupported(configuration, @"setGeneralStorageDirectory:", NMBDirectory(rootDirectory, @"GeneralStorage"));

    SEL initializer = NSSelectorFromString(@"_initWithConfiguration:");
    if (![WKWebsiteDataStore instancesRespondToSelector:initializer]) {
        return nil;
    }

    WKWebsiteDataStore *store = [[WKWebsiteDataStore alloc] _initWithConfiguration:configuration];
    return store.isPersistent ? store : nil;
}
