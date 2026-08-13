#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name("Tweak.xm")
text = path.read_text()
text = text.replace('#import <CoreMotion/CoreMotion.h>\n', '#import <CoreMotion/CoreMotion.h>\n#import <math.h>\n', 1)
text = text.replace('[NSDate date].descriptionWithLocale', '[NSDate date].description')
text = text.replace('[attributes fileSize] > 512 * 1024', '[attributes[NSFileSize] unsignedLongLongValue] > 512 * 1024')
text = text.replace(
    '@interface NQRQuickPanelController : UIViewController <UITextViewDelegate>\n',
    '@interface NQRQuickPanelController : UIViewController <UITextViewDelegate>\n- (instancetype)initWithTrigger:(NSString *)trigger;\n',
    1,
)
path.write_text(text)
print('Prepared Next Quick Reminder tweak source for compilation.')
