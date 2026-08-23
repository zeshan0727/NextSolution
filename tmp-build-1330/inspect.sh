#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
rm -rf "$R/appsrc" "$R/nqrsrc" "$R/inspect"
mkdir -p "$R/inspect/app" "$R/inspect/tweak"

# Reconstruct exact stable 1.3.29 app source, stopping before asset generation/Xcode build.
awk '/^ASSETS=/{exit} {print}' tmp-build-1329/build.sh > "$R/reconstruct-app.sh"
bash "$R/reconstruct-app.sh"

# Reconstruct exact Next Quick Reminder 1.0.14 source.
mkdir -p "$R/nqrsrc"
cat tmp-build/nqr1012/part-* > "$R/nqr.b64"
python3 - <<'PY'
import base64, os, pathlib
r=pathlib.Path(os.environ['RUNNER_TEMP'])
(r/'nqr.tar.xz').write_bytes(base64.b64decode((r/'nqr.b64').read_bytes()))
PY
echo 'eba18cc3ee4117e3e190441ce3533e10613a182aa610a3c92756c72a84cfd757  '"$R/nqr.tar.xz" | shasum -a 256 -c -
tar -xJf "$R/nqr.tar.xz" -C "$R/nqrsrc"
cat tmp-build-1325/patch/tweak-* > "$R/tweak.patch.xz.b64"
base64 -D < "$R/tweak.patch.xz.b64" > "$R/tweak.patch.xz"
xz -dc "$R/tweak.patch.xz" > "$R/tweak.patch"
patch -d "$R/nqrsrc" -p4 < "$R/tweak.patch"

P="$R/appsrc/NextReminder/Sources"
for f in App.swift ModelsUtilities.swift Services.swift PendingReports.swift RootReminders.swift EmailAutomationCore.swift EmailAutomationSettingsView.swift AutomationServices.swift Settings.swift; do
  test -f "$P/$f" && cp "$P/$f" "$R/inspect/app/$f"
done
cp "$R/appsrc/NextReminder.xcodeproj/project.pbxproj" "$R/inspect/app/project.pbxproj"

find "$R/nqrsrc" -maxdepth 3 -type f \( -name '*.m' -o -name '*.h' -o -name '*.xm' -o -name 'Makefile' -o -name 'control' -o -name '*.plist' \) -print -exec cp {} "$R/inspect/tweak/" \;

echo '--- APP STORAGE HINTS ---' > "$R/inspect/summary.txt"
grep -RniE 'reminders|json|UserDefaults|Application Support|Documents|encode|decode|save|load' "$P/ModelsUtilities.swift" "$P/Services.swift" "$P/App.swift" | head -n 240 >> "$R/inspect/summary.txt" || true
echo '--- TWEAK SENDER HINTS ---' >> "$R/inspect/summary.txt"
grep -RniE 'Pending|Report|Gmail|file-shares|LSApplicationProxy|container|preference|plist|timer|schedule' "$R/nqrsrc" | head -n 300 >> "$R/inspect/summary.txt" || true
