#import <Contacts/Contacts.h>
#import <objc/message.h>

/*
 * Apple exposes My Card publicly on macOS but marks the direct method
 * unavailable in the iOS SDK. MobilePhone/Siri builds may still provide one
 * of the equivalent runtime selectors. This adapter checks them safely and
 * returns nil when the current iOS build does not expose a My Card lookup.
 */
@interface CNContactStore (PhoneAuraMyCardBridge)
- (CNContact *)PA46DynamicMeContact:(NSArray<id<CNKeyDescriptor>> *)keys
                              error:(NSError **)error;
@end

@implementation CNContactStore (PhoneAuraMyCardBridge)

- (CNContact *)PA46DynamicMeContact:(NSArray<id<CNKeyDescriptor>> *)keys
                              error:(NSError **)error {
    NSArray<NSString *> *selectorNames = @[
        @"unifiedMeContactWithKeysToFetch:error:",
        @"_crossPlatformUnifiedMeContactWithKeysToFetch:error:",
        @"_unifiedMeContactWithKeysToFetch:error:",
        @"meContactWithKeysToFetch:error:"
    ];

    for (NSString *name in selectorNames) {
        SEL selector = NSSelectorFromString(name);
        if (![self respondsToSelector:selector]) continue;

        typedef id (*PA46MyCardFunction)(id, SEL, id, NSError **);
        PA46MyCardFunction function = (PA46MyCardFunction)objc_msgSend;
        @try {
            id contact = function(self, selector, keys, error);
            if ([contact isKindOfClass:[CNContact class]]) return contact;
        } @catch (__unused NSException *exception) {
        }
    }

    if (error) *error = nil;
    return nil;
}

@end

/* Rewrite only the source-level unavailable call after Contacts.h is parsed. */
#define unifiedMeContactWithKeysToFetch PA46DynamicMeContact
#include "PAContactFlowV46.m"
