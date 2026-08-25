#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Creates an isolated persistent WebKit store rooted at `rootDirectory` on
/// systems that predate WKWebsiteDataStore's public named-store API.
FOUNDATION_EXPORT WKWebsiteDataStore * _Nullable NMBCreatePersistentWebsiteDataStore(
    NSURL *rootDirectory
);

NS_ASSUME_NONNULL_END
