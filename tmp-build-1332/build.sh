#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
rm -rf "$R/appsrc" "$R/out" "$R/DD" "$R/iconvenv"
mkdir -p "$R/out"

# Reconstruct exact working 1.3.29 source and apply 1.3.30 automation UI patch.
awk '/^ASSETS=/{exit} {print}' tmp-build-1329/build.sh > "$R/reconstruct-app.sh"
bash "$R/reconstruct-app.sh"
P="$R/appsrc"
FILES_SHA=$(shasum -a 256 "$P/NextReminder/Sources/FileSharing.swift" | awk '{print $1}')
base64 -D < tmp-build-1330/app1330.patch.xz.b64 > "$R/app1330.patch.xz"
xz -dc "$R/app1330.patch.xz" > "$R/app1330.patch"
patch -d "$P" -p1 < "$R/app1330.patch"

# Patch only PendingReports.swift: add the same Gmail restore/retry behavior used by the working test-email path.
python3 - <<'PYFIX'
from pathlib import Path
import os
p=Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder/Sources/PendingReports.swift'
s=p.read_text()
start=s.index('    func send(\n        report: PendingReminderPDFReport,')
end=s.index('\n}\n\nstruct PendingReportsView: View', start)
old=s[start:end]
new=r'''    func send(
        report: PendingReminderPDFReport,
        recipient: String,
        gmail: GmailConnectionRecord,
        endpoint: String,
        apiKey: String
    ) async throws -> String {
        do {
            return try await sendOnce(
                report: report,
                recipient: recipient,
                gmail: gmail,
                endpoint: endpoint,
                apiKey: apiKey
            )
        } catch PendingReportEmailError.connectorExpired {
            return try await restoreAndRetry(
                report: report,
                recipient: recipient,
                gmail: gmail,
                endpoint: endpoint,
                apiKey: apiKey
            )
        } catch {
            guard GmailConnectionStore.isDisconnectionMessage(error.localizedDescription) else {
                throw error
            }
            return try await restoreAndRetry(
                report: report,
                recipient: recipient,
                gmail: gmail,
                endpoint: endpoint,
                apiKey: apiKey
            )
        }
    }

    private func restoreAndRetry(
        report: PendingReminderPDFReport,
        recipient: String,
        gmail: GmailConnectionRecord,
        endpoint: String,
        apiKey: String
    ) async throws -> String {
        let restored: GmailConnectionRecord
        do {
            restored = try await GmailOAuthClient.shared.restoreConnection(
                connectorID: gmail.connectorID
            )
        } catch {
            throw PendingReportEmailError.server(
                "Gmail connector recovery failed: \(error.localizedDescription)"
            )
        }

        // Keep Email Automation settings synchronized if the scheduler returns
        // a refreshed connector ID during recovery.
        var settings = EmailAutomationSettings.load()
        settings.deliveryMethod = .gmailAutomatic
        settings.remoteConnectorID = restored.connectorID
        if !restored.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.senderLabel = restored.emailAddress
        }
        settings.persist()
        NotificationCenter.default.post(name: .nextEmailAutomationSettingsChanged, object: nil)

        do {
            return try await sendOnce(
                report: report,
                recipient: recipient,
                gmail: restored,
                endpoint: endpoint,
                apiKey: apiKey
            )
        } catch PendingReportEmailError.connectorExpired {
            throw PendingReportEmailError.server(
                "Gmail was restored, but the scheduler still rejected the report attachment. Reconnect Gmail once and try again."
            )
        }
    }

    private func sendOnce(
        report: PendingReminderPDFReport,
        recipient: String,
        gmail: GmailConnectionRecord,
        endpoint: String,
        apiKey: String
    ) async throws -> String {
        let recipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(recipient) else { throw PendingReportEmailError.invalidRecipient }
        guard !gmail.connectorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PendingReportEmailError.gmailNotConnected
        }
        guard !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PendingReportEmailError.schedulerNotConfigured
        }

        let normalized = endpoint.hasSuffix("/") ? endpoint : endpoint + "/"
        guard let baseURL = URL(string: normalized),
              baseURL.scheme?.lowercased() == "https",
              let url = URL(string: "v1/file-shares", relativeTo: baseURL)?.absoluteURL else {
            throw PendingReportEmailError.invalidEndpoint
        }

        let data: Data
        do {
            data = try Data(contentsOf: report.url, options: [.mappedIfSafe])
        } catch {
            throw PendingReportEmailError.unreadablePDF
        }
        guard !data.isEmpty else { throw PendingReportEmailError.unreadablePDF }
        guard data.count <= 8_000_000 else { throw PendingReportEmailError.attachmentTooLarge }

        let payload = PendingReportEmailPayload(
            recipients: [recipient],
            subject: "Pending Reminders Report — \(report.reminderCount)",
            body: "Please find attached the pending reminders report generated by Next Reminder on \(report.createdAt.formatted(date: .long, time: .shortened)).",
            remoteConnectorID: gmail.connectorID,
            senderLabel: gmail.emailAddress,
            attachments: [
                PendingReportEmailAttachment(
                    fileName: report.fileName,
                    mimeType: "application/pdf",
                    base64: data.base64EncodedString()
                )
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("NextReminder-iOS/1.3.31.41", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(payload)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PendingReportEmailError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(PendingReportEmailResponse.self, from: responseData).message)
                ?? "PDF email failed (\(http.statusCode))."
            if GmailConnectionStore.isDisconnectionMessage(message) {
                throw PendingReportEmailError.connectorExpired
            }
            throw PendingReportEmailError.server("Report send failed (HTTP \(http.statusCode)): \(message)")
        }

        return (try? JSONDecoder().decode(PendingReportEmailResponse.self, from: responseData).message)
            ?? "PDF sent successfully."
    }
'''
s=s[:start]+new+s[end:]
p.write_text(s)
PYFIX

# Bump app + Live Activity to 1.3.31 build 41.
python3 - <<'PYVER'
from pathlib import Path
import os,re
root=Path(os.environ['RUNNER_TEMP'])/'appsrc'
pbx=root/'NextReminder.xcodeproj/project.pbxproj'
s=pbx.read_text()
s=re.sub(r'CURRENT_PROJECT_VERSION = 39;', 'CURRENT_PROJECT_VERSION = 41;', s)
s=re.sub(r'MARKETING_VERSION = 1\.3\.29;', 'MARKETING_VERSION = 1.3.31;', s)
pbx.write_text(s)
for rel in ['NextReminder/Resources/Info.plist','NextReminderLiveActivity/Info.plist']:
    p=root/rel
    if p.exists():
        t=p.read_text().replace('<string>1.3.29</string>','<string>1.3.31</string>').replace('<string>39</string>','<string>41</string>')
        p.write_text(t)
PYVER

# Regression guards.
test "$(shasum -a 256 "$P/NextReminder/Sources/FileSharing.swift" | awk '{print $1}')" = "$FILES_SHA"
! grep -q 'PendingReminderPDFReport' "$P/NextReminder/Sources/FileSharing.swift"
grep -q 'restoreAndRetry' "$P/NextReminder/Sources/PendingReports.swift"
grep -q 'GmailOAuthClient.shared.restoreConnection' "$P/NextReminder/Sources/PendingReports.swift"
grep -q 'Report send failed (HTTP' "$P/NextReminder/Sources/PendingReports.swift"
grep -q 'NextReminder-iOS/1.3.31.41' "$P/NextReminder/Sources/PendingReports.swift"

# Restore icon catalog exactly as the working release family.
ASSETS="$P/NextReminder/Resources/Assets.xcassets"
ICONSET="$ASSETS/AppIcon.appiconset"
mkdir -p "$ICONSET" "$ASSETS/AccentColor.colorset" "$ASSETS/LaunchBackground.colorset"
python3 -m venv "$R/iconvenv"
"$R/iconvenv/bin/pip" install --quiet pillow
"$R/iconvenv/bin/python" - <<'PYICON'
from PIL import Image, ImageDraw
from pathlib import Path
import os,json
root=Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder/Resources/Assets.xcassets/AppIcon.appiconset'
root.mkdir(parents=True,exist_ok=True)
S=1024
img=Image.new('RGB',(S,S),(18,18,22)); d=ImageDraw.Draw(img)
for r in range(720,0,-8):
    t=r/720; col=(int(255-(45*t)), int(103-(45*t)), int(28-(12*t)))
    d.ellipse((S/2-r,S/2-r,S/2+r,S/2+r),fill=col)
d.rounded_rectangle((190,205,834,820),radius=145,fill=(25,25,30),outline=(255,255,255),width=10)
d.ellipse((410,330,614,534),fill=(255,255,255)); d.rounded_rectangle((390,430,634,625),radius=80,fill=(255,255,255)); d.rectangle((365,575,659,625),fill=(255,255,255)); d.ellipse((474,630,550,706),fill=(255,255,255)); d.ellipse((585,560,755,730),fill=(255,116,38),outline=(25,25,30),width=12); d.line((625,645,665,683),fill='white',width=22); d.line((665,683,724,616),fill='white',width=22)
img.save(root/'AppIcon-1024.png',optimize=True)
for size in [40,58,60,80,87,120,180]: img.resize((size,size),Image.Resampling.LANCZOS).save(root/f'AppIcon-{size}.png',optimize=True)
contents={"images":[{"filename":"AppIcon-40.png","idiom":"iphone","scale":"2x","size":"20x20"},{"filename":"AppIcon-60.png","idiom":"iphone","scale":"3x","size":"20x20"},{"filename":"AppIcon-58.png","idiom":"iphone","scale":"2x","size":"29x29"},{"filename":"AppIcon-87.png","idiom":"iphone","scale":"3x","size":"29x29"},{"filename":"AppIcon-80.png","idiom":"iphone","scale":"2x","size":"40x40"},{"filename":"AppIcon-120.png","idiom":"iphone","scale":"3x","size":"40x40"},{"filename":"AppIcon-120.png","idiom":"iphone","scale":"2x","size":"60x60"},{"filename":"AppIcon-180.png","idiom":"iphone","scale":"3x","size":"60x60"},{"filename":"AppIcon-1024.png","idiom":"ios-marketing","scale":"1x","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
(root/'Contents.json').write_text(json.dumps(contents,indent=2)+'\n')
(root.parent/'Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')
PYICON
cat > "$ASSETS/AccentColor.colorset/Contents.json" <<'EOF2'
{"colors":[],"info":{"author":"xcode","version":1}}
EOF2
cat > "$ASSETS/LaunchBackground.colorset/Contents.json" <<'EOF2'
{"colors":[],"info":{"author":"xcode","version":1}}
EOF2

grep -q 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;' "$P/NextReminder.xcodeproj/project.pbxproj"
xcodebuild -project "$P/NextReminder.xcodeproj" -scheme NextReminder \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$R/DD" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
APP=$(find "$R/DD/Build/Products/Release-iphoneos" -maxdepth 1 -name NextReminder.app -print -quit)
test -n "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")" = '1.3.31'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")" = '41'
EXT="$APP/PlugIns/NextReminderLiveActivity.appex/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXT")" = '1.3.31'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXT")" = '41'
test -f "$APP/Assets.car"
strings "$APP/NextReminder" > "$R/app.strings"
grep -q 'Gmail connector recovery failed' "$R/app.strings"
grep -q 'Report send failed (HTTP' "$R/app.strings"

mkdir -p "$R/out/Payload"
cp -R "$APP" "$R/out/Payload/"
(cd "$R/out" && zip -qry NextReminder_1.3.31_Unsigned.tipa Payload)
rm -rf "$R/out/Payload"
cd "$R/out"
shasum -a 256 NextReminder_1.3.31_Unsigned.tipa > SHA256SUMS.txt
ls -lh
cat SHA256SUMS.txt
