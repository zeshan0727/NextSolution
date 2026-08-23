#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
mkdir -p "$R/appsrc" "$R/nqrsrc" "$R/out"
python3 - <<'PYFIX'
from pathlib import Path
p=Path('tmp-build/nr1322xz/part-09')
f=Path('tmp-build/appfix/part09-block6000.txt').read_bytes()
b=bytearray(p.read_bytes())
assert len(b)==10000 and len(f)==500
b[6000:6500]=f
p.write_bytes(b)
PYFIX
cat tmp-build/nr1322xz/part-* > "$R/nr.b64"
cat tmp-build/nqr1012/part-* > "$R/nqr.b64"
python3 - <<'PYDEC'
import base64,os,pathlib
r=pathlib.Path(os.environ['RUNNER_TEMP'])
(r/'nr.tar.xz').write_bytes(base64.b64decode((r/'nr.b64').read_bytes()))
(r/'nqr.tar.xz').write_bytes(base64.b64decode((r/'nqr.b64').read_bytes()))
PYDEC
echo '8334365b7095d7fb3b1cbe92a08a837c097a6ca3b6de7f34765d2541ceaf0046  '"$R/nr.tar.xz" | shasum -a 256 -c -
echo 'eba18cc3ee4117e3e190441ce3533e10613a182aa610a3c92756c72a84cfd757  '"$R/nqr.tar.xz" | shasum -a 256 -c -
tar -xJf "$R/nr.tar.xz" -C "$R/appsrc"
tar -xJf "$R/nqr.tar.xz" -C "$R/nqrsrc"

python3 - <<'PYAPP'
from pathlib import Path
import os
r=Path(os.environ['RUNNER_TEMP'])
p=r/'appsrc/NextReminder/Sources/AutomationServices.swift'
s=p.read_text()
s=s.replace('private static let account = "scheduler-api-key"', 'private static let account = "scheduler-api-key"\n    private static let quickReportBridgeKey = "NextReminder.QuickReportBridgeAPIKey.v1"')
s=s.replace('        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {\n            throw AutomationError.secureStorage\n        }\n', '        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {\n            throw AutomationError.secureStorage\n        }\n        UserDefaults.standard.set(value, forKey: quickReportBridgeKey)\n', 1)
s=s.replace('        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,\n              let data = result as? Data else {\n            return ""\n        }\n        return String(data: data, encoding: .utf8) ?? ""\n', '        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,\n              let data = result as? Data else {\n            return ""\n        }\n        let value = String(data: data, encoding: .utf8) ?? ""\n        if !value.isEmpty { UserDefaults.standard.set(value, forKey: quickReportBridgeKey) }\n        return value\n', 1)
s=s.replace('        SecItemDelete(query as CFDictionary)\n    }\n}\n', '        SecItemDelete(query as CFDictionary)\n        UserDefaults.standard.removeObject(forKey: quickReportBridgeKey)\n    }\n}\n', 1)
p.write_text(s)
plist=r/'appsrc/NextReminder/Resources/Info.plist'
s=plist.read_text().replace('<string>1.3.22</string>','<string>1.3.23</string>').replace('<string>32</string>','<string>33</string>')
plist.write_text(s)
pbx=r/'appsrc/NextReminder.xcodeproj/project.pbxproj'
s=pbx.read_text().replace('MARKETING_VERSION = 1.3.22;','MARKETING_VERSION = 1.3.23;').replace('CURRENT_PROJECT_VERSION = 32;','CURRENT_PROJECT_VERSION = 33;')
pbx.write_text(s)
PYAPP

cat > "$R/nqrsrc/PendingReportSender.h" <<'EOFH'
#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void NQRSendPendingReportInBackground(void);
EOFH
cp tmp-build/PendingReportSender-1013.m "$R/nqrsrc/PendingReportSender.m"
python3 - <<'PYTWEAK'
from pathlib import Path
import os
r=Path(os.environ['RUNNER_TEMP'])/'nqrsrc'
p=r/'Tweak.xm'; s=p.read_text()
s=s.replace('#import <substrate.h>', '#import <substrate.h>\n#import "PendingReportSender.h"')
marker='static void NQROpenPendingReport(void) {'
start=s.index(marker, s.index('static void NQROpenQuickForm'))
end=s.index('\nstatic void NQRDismissPanel(void)', start)
new='''static void NQROpenPendingReport(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NQRLog(@"Send Report selected; starting background delivery without launching Next Reminder");
        NQRDismissPanel();
        NQRSendPendingReportInBackground();
    });
}
'''
s=s[:start]+new+s[end:]
s=s.replace('Next Quick Reminder 1.0.12 loaded with quick action chooser and pending report shortcut', 'Next Quick Reminder 1.0.13 loaded with background pending-report sender')
p.write_text(s)
m=r/'Makefile'; s=m.read_text()
s=s.replace('NextQuickReminder_FILES = Tweak.xm ConsoleBridge.m BackgroundLockscreen.xm MultiTriggersSettings.xm SystemApertureReminderV109.xm','NextQuickReminder_FILES = Tweak.xm PendingReportSender.m ConsoleBridge.m BackgroundLockscreen.xm MultiTriggersSettings.xm SystemApertureReminderV109.xm')
s=s.replace('NextQuickReminder_FRAMEWORKS = UIKit Foundation CoreMotion UserNotifications','NextQuickReminder_FRAMEWORKS = UIKit Foundation CoreMotion UserNotifications Security')
m.write_text(s)
c=r/'control'; c.write_text(c.read_text().replace('Version: 1.0.12','Version: 1.0.13'))
PYTWEAK

P="$R/appsrc"
mkdir -p "$P/NextReminder/Resources/Assets.xcassets"
printf '%s\n' '{"info":{"author":"xcode","version":1}}' > "$P/NextReminder/Resources/Assets.xcassets/Contents.json"
python3 - <<'PYASSET'
import os,pathlib
p=pathlib.Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder.xcodeproj/project.pbxproj'
s=p.read_text().splitlines()
p.write_text('\n'.join(x for x in s if 'ASSETCATALOG_COMPILER_APPICON_NAME' not in x and 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' not in x)+'\n')
PYASSET
xcodebuild -project "$P/NextReminder.xcodeproj" -scheme NextReminder -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$R/DD" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
APP=$(find "$R/DD/Build/Products/Release-iphoneos" -maxdepth 1 -name NextReminder.app -print -quit)
test -n "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")" = 1.3.23
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")" = 33
strings "$APP/NextReminder" | grep -q 'NextReminder.QuickReportBridgeAPIKey.v1'
mkdir -p "$R/out/Payload"; cp -R "$APP" "$R/out/Payload/"
(cd "$R/out" && zip -qry NextReminder_1.3.23_Unsigned.tipa Payload)
rm -rf "$R/out/Payload"

grep -R -q 'NQRSendPendingReportInBackground' "$R/nqrsrc"
grep -R -q 'v1/email-reminders/test' "$R/nqrsrc/PendingReportSender.m"
! grep -q 'nextreminder://send-report' "$R/nqrsrc/Tweak.xm"
brew install dpkg ldid
T="$R/theos-rh"; git init "$T"; git -C "$T" remote add origin https://github.com/roothide/theos.git
git -C "$T" fetch --depth 1 origin 88506b2c22e9e07dd4ed055f23c9e398a117a2c7
git -C "$T" checkout --detach 88506b2c22e9e07dd4ed055f23c9e398a117a2c7
git -C "$T" submodule update --init --recursive --depth 1
export THEOS="$T" THEOS_PACKAGE_SCHEME=roothide
make -C "$R/nqrsrc" clean package FINALPACKAGE=1
D=$(find "$R/nqrsrc/packages" -name '*.deb' -print -quit); test -n "$D"
test "$(dpkg-deb -f "$D" Version)" = 1.0.13
X=$(mktemp -d); dpkg-deb -x "$D" "$X"; F=$(find "$X" -name NextQuickReminder.dylib -print -quit); test -n "$F"
strings -a "$F" | grep -q 'Sending report'
strings -a "$F" | grep -q 'Report sent'
strings -a "$F" | grep -q 'v1/email-reminders/test'
cp "$D" "$R/out/NextQuickReminder_1.0.13_RootHide.deb"
cd "$R/out"
shasum -a 256 NextReminder_1.3.23_Unsigned.tipa NextQuickReminder_1.0.13_RootHide.deb > SHA256SUMS.txt
ls -lh
