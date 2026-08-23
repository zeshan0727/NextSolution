#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
# Reuse the exact 1.3.28 reconstruction/rollback logic, but stop before icon/build work.
awk '/# Restore\/compile a complete icon catalog/{exit} {print}' tmp-build-1328/build.sh > "$R/reconstruct-1328.sh"
bash "$R/reconstruct-1328.sh"
mkdir -p "$R/inspect"
for f in App.swift RootReminders.swift Settings.swift EmailAutomationCore.swift GmailConnection.swift AutomationServices.swift FileSharing.swift ModelsUtilities.swift; do
  cp "$R/appsrc/NextReminder/Sources/$f" "$R/inspect/$f"
done
cp "$R/appsrc/NextReminder.xcodeproj/project.pbxproj" "$R/inspect/project.pbxproj"
ls -lh "$R/inspect"
