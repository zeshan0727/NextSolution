#!/bin/sh
set -eu

ROOT="${1:-DailyLedger}"

if [ ! -d "$ROOT" ]; then
  echo "App Store source directory not found: $ROOT" >&2
  exit 2
fi

PATTERN='OpenAI|DeepSeek|RootHide|TrollStore|Sileo|jailbreak|MobileSMS|IMDPersistence|LSApplicationWorkspace|Z-iP-14PM-16\.0|/private/var|SpringBoard'

if grep -RniE \
  --include='*.swift' \
  --include='*.m' \
  --include='*.mm' \
  --include='*.h' \
  --include='*.plist' \
  --include='*.entitlements' \
  "$PATTERN" "$ROOT"; then
  echo "\nBlocked: rejection-risk source markers were found in the App Store target." >&2
  exit 1
fi

echo "App Store source marker scan passed."
