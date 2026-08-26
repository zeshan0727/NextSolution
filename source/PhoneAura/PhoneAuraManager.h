#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PhoneAuraManager : NSObject
+ (instancetype)sharedManager;
- (void)controllerDidAppear:(UIViewController *)controller;
- (void)controllerDidLayout:(UIViewController *)controller;
- (void)tabSelectionChanged:(UITabBarController *)tabController;
- (void)reloadPreferences;
@end

NS_ASSUME_NONNULL_END
