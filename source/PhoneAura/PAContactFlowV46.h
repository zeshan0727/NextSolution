#import <UIKit/UIKit.h>
#import <Contacts/Contacts.h>

NS_ASSUME_NONNULL_BEGIN

@interface PAFavoritesDashboardV46 : UIView
@property(nonatomic,copy) void (^callHandler)(NSString *number);
@property(nonatomic,copy) void (^chooseHandler)(void);
@property(nonatomic) BOOL hapticsEnabled;
- (void)reloadFavoriteIdentifiers:(NSArray<NSString *> *)identifiers;
@end

@interface PAContactsDashboardV46 : UIView
@property(nonatomic,copy) void (^contactHandler)(CNContact *contact);
@property(nonatomic) BOOL hapticsEnabled;
- (void)refresh;
@end

@interface PAFavoritePickerViewV46 : UIView
@property(nonatomic,copy) void (^saveHandler)(NSArray<NSString *> *identifiers);
@property(nonatomic) BOOL hapticsEnabled;
- (void)reloadSelectedIdentifiers:(NSArray<NSString *> *)identifiers;
@end

@interface PAContactDetailViewV46 : UIView
@property(nonatomic,copy) void (^callHandler)(NSString *number);
@property(nonatomic) BOOL hapticsEnabled;
- (void)configureContact:(CNContact *)contact;
@end

NS_ASSUME_NONNULL_END
