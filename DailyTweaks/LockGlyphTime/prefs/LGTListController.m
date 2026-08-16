#import <Preferences/PSListController.h>

@interface LGTListController : PSListController
@end

@implementation LGTListController
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}
@end
