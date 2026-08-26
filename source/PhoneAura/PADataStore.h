#import <Foundation/Foundation.h>
#import <Contacts/Contacts.h>

NS_ASSUME_NONNULL_BEGIN

@interface PARecentCall : NSObject
@property(nonatomic,copy) NSString *number;
@property(nonatomic,copy) NSString *displayName;
@property(nonatomic,strong) NSDate *date;
@property(nonatomic) NSTimeInterval duration;
@property(nonatomic) BOOL missed;
@property(nonatomic) BOOL outgoing;
@end

@interface PADataStore : NSObject
+ (instancetype)sharedStore;
- (void)favoriteContactsForIdentifiers:(NSArray<NSString *> *)identifiers
                            completion:(void (^)(NSArray<CNContact *> *contacts))completion;
- (void)allContactsWithCompletion:(void (^)(NSArray<CNContact *> *contacts))completion;
- (void)recentCallsMissedOnly:(BOOL)missedOnly
                        limit:(NSUInteger)limit
                   completion:(void (^)(NSArray<PARecentCall *> *calls))completion;
@end

NS_ASSUME_NONNULL_END
