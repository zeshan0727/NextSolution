#import <UIKit/UIKit.h>
#import <Contacts/Contacts.h>

NS_ASSUME_NONNULL_BEGIN

@interface PAFavoritesDashboardView : UIView
@property(nonatomic,copy) void (^callHandler)(NSString *number);
@property(nonatomic,copy) void (^settingsHandler)(void);
@property(nonatomic) BOOL hapticsEnabled;
- (void)reloadFavoriteIdentifiers:(NSArray<NSString *> *)identifiers;
@end

@interface PARecentsDashboardView : UIView
@property(nonatomic,copy) void (^callHandler)(NSString *number);
@property(nonatomic) BOOL hapticsEnabled;
- (void)refresh;
@end

@interface PAContactsDashboardView : UIView
@property(nonatomic,copy) void (^contactHandler)(CNContact *contact);
@property(nonatomic) BOOL hapticsEnabled;
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
