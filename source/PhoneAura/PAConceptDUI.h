#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

UIColor *PAColorHex(uint32_t hex, CGFloat alpha);
UIColor *PAAccentForIndex(NSUInteger index);
NSArray<UIColor *> *PAPaletteForIndex(NSUInteger index);

@interface PAStudioHeaderView : UIView
@property(nonatomic,copy) void (^actionHandler)(void);
- (void)configureTitle:(NSString *)title
              subtitle:(NSString *)subtitle
                  icon:(NSString *)icon
                accent:(UIColor *)accent
          showSubtitle:(BOOL)showSubtitle;
@end

@interface PAStudioDock : UIView
@property(nonatomic,copy) void (^selectionHandler)(NSUInteger index);
- (void)updateSelectedIndex:(NSUInteger)selectedIndex animated:(BOOL)animated;
@end

@interface PAStudioCardBackgroundView : UIView
- (void)configureForTab:(NSUInteger)tabIndex
                    row:(NSUInteger)row
                opacity:(CGFloat)opacity
           cornerRadius:(CGFloat)cornerRadius;
@end

@interface PAStudioShortcutsView : UIView
@property(nonatomic,copy) void (^tapHandler)(NSUInteger index);
@end

@interface PAStudioKeypadView : UIView
@property(nonatomic) BOOL hapticsEnabled;
@property(nonatomic) BOOL animationsEnabled;
@property(nonatomic) CGFloat studioCornerRadius;
- (void)clearNumber;
@end

NS_ASSUME_NONNULL_END
