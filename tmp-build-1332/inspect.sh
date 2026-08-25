#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
rm -rf "$R/appsrc" "$R/inspect"
mkdir -p "$R/inspect"

# Reconstruct exact 1.3.29 source, then apply the 1.3.30 automation UI patch.
awk '/^ASSETS=/{exit} {print}' tmp-build-1329/build.sh > "$R/reconstruct-app.sh"
bash "$R/reconstruct-app.sh"
P="$R/appsrc"
base64 -D < tmp-build-1330/app1330.patch.xz.b64 > "$R/app1330.patch.xz"
xz -dc "$R/app1330.patch.xz" > "$R/app1330.patch"
patch -d "$P" -p1 < "$R/app1330.patch"

cp -R "$P/NextReminder/Sources" "$R/inspect/Sources"
{
  echo '=== GMAIL / CONNECTOR / SEND HITS ==='
  grep -R -n -E 'GmailConnectionStore|connectorID|remoteConnectorID|v1/file-shares|v1/.*email|Test Gmail|Test Connection|testConnection|test.*connector|email-schedules|cloudEndpoint|cloudAPIKey' "$P/NextReminder/Sources" || true
} > "$R/inspect/hits.txt"

tar -czf "$R/inspect/NextReminder-1.3.30-Sources.tgz" -C "$P/NextReminder" Sources
