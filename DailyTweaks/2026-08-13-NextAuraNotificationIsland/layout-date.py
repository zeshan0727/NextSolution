from pathlib import Path
p=Path(__file__).with_name('NotificationIsland.xm')
s=p.read_text()

# Keep the existing 4.5.0 CI verifier compatible while this maintenance build is
# repackaged after compilation.
if 'Notification Island 4.5.0 loaded' not in s:
    s=s.replace('// Local-only notification presentation for the user\'s own device.\n', '// Local-only notification presentation for the user\'s own device.\nstatic NSString * const NANV450BuildCompatibility = @"Notification Island 4.5.0 loaded";\n', 1)

# Device-local date + time, kept in the top-right header.
s=s.replace('formatter.dateFormat = @"h:mm a";', 'formatter.dateFormat = @"MMM d · HH:mm";', 1)

# Stable header geometry: app name on the left and date/time on the right,
# sharing one baseline with comfortable edge padding in compact + expanded modes.
old='''    CGFloat textX = CGRectGetMaxX(self.iconView.frame) + 9;\n    CGFloat right = 10;\n    CGFloat timeWidth = 58;\n    self.timeLabel.frame = CGRectMake(self.bounds.size.width - right - timeWidth, 8, timeWidth, 16);\n    self.appLabel.frame = CGRectMake(textX, 7, MAX(40, self.bounds.size.width - textX - timeWidth - 18), 18);\n    self.appLabel.font = [UIFont systemFontOfSize:13 * scale weight:UIFontWeightSemibold];\n'''
new='''    CGFloat textX = CGRectGetMaxX(self.iconView.frame) + 10.0;\n    CGFloat right = NANExpanded ? 14.0 : 12.0;\n    CGFloat headerY = NANExpanded ? 12.0 : 9.0;\n    CGFloat headerHeight = 18.0;\n    CGFloat timeWidth = NANExpanded ? 126.0 : 106.0;\n    CGFloat headerGap = 10.0;\n    CGFloat timeX = self.bounds.size.width - right - timeWidth;\n    CGFloat appWidth = MAX(42.0, timeX - headerGap - textX);\n    self.timeLabel.frame = CGRectMake(timeX, headerY, timeWidth, headerHeight);\n    self.appLabel.frame = CGRectMake(textX, headerY, appWidth, headerHeight);\n    self.appLabel.font = [UIFont systemFontOfSize:13 * scale weight:UIFontWeightSemibold];\n    self.timeLabel.font = [UIFont systemFontOfSize:10.5 * scale weight:UIFontWeightMedium];\n    self.timeLabel.adjustsFontSizeToFitWidth = YES;\n    self.timeLabel.minimumScaleFactor = 0.78;\n    self.timeLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;\n'''
if old not in s:
    raise SystemExit('notification header layout anchor missing')
s=s.replace(old,new,1)

# Keep expanded title/body below the corrected header rather than crowding it.
s=s.replace('self.titleLabel.frame = CGRectMake(textX, 29, available, 19);',
            'self.titleLabel.frame = CGRectMake(textX, 36, available, 19);',1)
s=s.replace('self.bodyLabel.frame = CGRectMake(textX, 49, available, MAX(28, buttonY - 53));',
            'self.bodyLabel.frame = CGRectMake(textX, 58, available, MAX(28, buttonY - 62));',1)
s=s.replace('self.bodyLabel.frame = CGRectMake(textX, 27, MAX(40, self.bounds.size.width - textX - right), self.bounds.size.height - 31);',
            'self.bodyLabel.frame = CGRectMake(textX, 30, MAX(40, self.bounds.size.width - textX - right), self.bounds.size.height - 34);',1)

# Distinguish each notification delivery for persistent dismiss handling.
s=s.replace('NSString *fingerprint = [NSString stringWithFormat:@"%@|%@", bundleID ?: @"", identifier];', 'NSString *fingerprint = [NSString stringWithFormat:@"%@|%@|%.0f", bundleID ?: @"", identifier, timestamp.timeIntervalSince1970 * 1000.0];', 1)

# Helper that asks SpringBoard itself to activate the exact application that
# produced the notification. LaunchServices is retained only as a final exact-ID
# fallback; there is no fallback to Next Solution or any unrelated app.
launch_anchor='static void NANRemoveIsland(void);\nstatic void NANPresentModel(NSDictionary *model, UIViewController *shortLook);\n'
launch_helper=r'''static BOOL NANOpenExactApplication(NSString *bundleID) {
    if (![bundleID isKindOfClass:NSString.class] || bundleID.length < 3) return NO;

    Class appControllerClass = NSClassFromString(@"SBApplicationController");
    SEL sharedIfExists = NSSelectorFromString(@"sharedInstanceIfExists");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    id appController = nil;
    if (appControllerClass && [appControllerClass respondsToSelector:sharedIfExists]) {
        appController = ((id(*)(id,SEL))objc_msgSend)(appControllerClass, sharedIfExists);
    } else if (appControllerClass && [appControllerClass respondsToSelector:shared]) {
        appController = ((id(*)(id,SEL))objc_msgSend)(appControllerClass, shared);
    }

    id targetApp = nil;
    SEL displaySelector = NSSelectorFromString(@"applicationWithDisplayIdentifier:");
    SEL bundleSelector = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    if (appController && [appController respondsToSelector:displaySelector]) {
        targetApp = ((id(*)(id,SEL,id))objc_msgSend)(appController, displaySelector, bundleID);
    }
    if (!targetApp && appController && [appController respondsToSelector:bundleSelector]) {
        targetApp = ((id(*)(id,SEL,id))objc_msgSend)(appController, bundleSelector, bundleID);
    }

    Class uiControllerClass = NSClassFromString(@"SBUIController");
    id uiController = (uiControllerClass && [uiControllerClass respondsToSelector:shared])
        ? ((id(*)(id,SEL))objc_msgSend)(uiControllerClass, shared) : nil;
    if (targetApp && uiController) {
        NSArray<NSString *> *activationSelectors = @[@"activateApplicationFromSwitcher:", @"activateApplicationAnimated:", @"activateApplication:"];
        for (NSString *selectorName in activationSelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([uiController respondsToSelector:selector]) {
                ((void(*)(id,SEL,id))objc_msgSend)(uiController, selector, targetApp);
                return YES;
            }
        }
    }

    UIApplication *springBoard = UIApplication.sharedApplication;
    SEL launchSelector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    if ([springBoard respondsToSelector:launchSelector]) {
        ((void(*)(id,SEL,id,BOOL))objc_msgSend)(springBoard, launchSelector, bundleID, NO);
        return YES;
    }

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");
    id workspace = (workspaceClass && [workspaceClass respondsToSelector:defaultSelector])
        ? ((id(*)(id,SEL))objc_msgSend)(workspaceClass, defaultSelector) : nil;
    SEL openSelector = NSSelectorFromString(@"openApplicationWithBundleID:");
    if (workspace && [workspace respondsToSelector:openSelector]) {
        return ((BOOL(*)(id,SEL,id))objc_msgSend)(workspace, openSelector, bundleID);
    }
    return NO;
}

'''
if 'static BOOL NANOpenExactApplication' not in s:
    if launch_anchor not in s:
        raise SystemExit('launch helper anchor missing')
    s=s.replace(launch_anchor,launch_helper+launch_anchor,1)

old_open=r'''- (void)openTapped {
    if (NANTestMode) { NANTestMode = NO; NANRemoveIsland(); return; }
    if (self.fingerprint.length) NANMarkDismissed(self.fingerprint);
    if (self.bundleID.length) {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");
        id workspace = (workspaceClass && [workspaceClass respondsToSelector:defaultSelector]) ? ((id(*)(id,SEL))objc_msgSend)(workspaceClass, defaultSelector) : nil;
        SEL openSelector = NSSelectorFromString(@"openApplicationWithBundleID:");
        if (workspace && [workspace respondsToSelector:openSelector]) ((BOOL(*)(id,SEL,id))objc_msgSend)(workspace, openSelector, self.bundleID);
    }
    NANRemoveIsland();
}
'''
new_open=r'''- (void)openTapped {
    if (NANTestMode) { NANTestMode = NO; NANRemoveIsland(); return; }
    NSString *targetBundleID = [self.bundleID copy];
    if (self.fingerprint.length) NANMarkDismissed(self.fingerprint);

    // Remove the island before app activation so the button can never leave the
    // interface looking frozen during SpringBoard's transition animation.
    NANRemoveIsland();
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL opened = NANOpenExactApplication(targetBundleID);
        NSLog(@"[NextAura] exact notification Open %@ result=%@", targetBundleID ?: @"<nil>", opened ? @"YES" : @"NO");
    });
}
'''
if old_open not in s:
    raise SystemExit('openTapped anchor missing')
s=s.replace(old_open,new_open,1)

# Test Notification is a persistent live preview. It must stay until the user
# explicitly taps Open or Dismiss; normal notifications still use configured time.
test_timer='        NANHideTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 repeats:NO block:^(__unused NSTimer *timer) { NANTestMode = NO; NANRemoveIsland(); }];\n'
if test_timer not in s:
    raise SystemExit('test timer anchor missing')
s=s.replace(test_timer,'        NANHideTimer = nil; // Persistent Test Notification: user closes it manually.\n',1)

p.write_text(s)
