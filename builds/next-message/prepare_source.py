from pathlib import Path

root = Path('build-work/NextMessageTweak')
tweak_path = root / 'Tweak.xm'
makefile_path = root / 'Makefile'

tweak = tweak_path.read_text()
marker = '#import "NMFilterBarView.h"\n'
declarations = r'''

// Minimal compile-time declarations for the private ChatKit controllers.
// Runtime availability is still checked by Logos when the tweak loads.
@interface CKConversationListViewController : UIViewController
- (UITableView *)tableView;
- (void)_newConversation:(id)sender;
- (void)nm_composeTapped;
- (void)nm_presentThemePicker;
@end

@interface CKConversationViewController : UIViewController
- (void)nm_refreshSmartReplyWithText:(NSString *)incomingText;
- (void)nm_sendQuickReply:(NSString *)text;
- (void)nm_showMessageCountToast;
@end
'''
if declarations.strip() not in tweak:
    tweak = tweak.replace(marker, marker + declarations, 1)
tweak_path.write_text(tweak)

makefile = makefile_path.read_text()
makefile = makefile.replace(
    'NextMessageTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations',
    'NextMessageTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-unguarded-availability-new'
)
makefile_path.write_text(makefile)

print('Applied CI compile compatibility fixes.')
