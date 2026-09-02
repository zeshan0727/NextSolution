#!/usr/bin/env bash
set -euo pipefail

# files.nextjailbreak.com is not yet configured in Cloudflare DNS/R2 custom domains.
# Override the workflow-level value at runtime so signing/publish steps use the
# existing public R2 hostname that currently resolves and serves this bucket.
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "R2_PUBLIC_BASE=https://files.nextsolution.cc" >> "$GITHUB_ENV"
fi

STATE="${1:-running}"
STAGE="${2:-Unknown}"
MESSAGE="${3:-Working}"
REQUEST_ID="${REQUEST_ID:-}"
INBOX_TAG="${INBOX_TAG:-nextsigner-inbox}"

if [ -z "$REQUEST_ID" ]; then
  exit 0
fi

if [ "$STATE" = "running" ]; then
  echo "CURRENT_STAGE=$STAGE" >> "$GITHUB_ENV"
fi

STAMP="$(date +%s%N)"
STATUS_NAME="status-$REQUEST_ID-$STAMP.json"
STATUS_FILE="$RUNNER_TEMP/$STATUS_NAME"
python3 - "$REQUEST_ID" "$STATE" "$STAGE" "$MESSAGE" "$GITHUB_RUN_ID" "$GITHUB_REPOSITORY" "$STATUS_FILE" <<'PY'
import json, sys
from datetime import datetime, timezone
request_id, state, stage, message, run_id, repository, path = sys.argv[1:]
payload = {
    "request_id": request_id,
    "state": state,
    "stage": stage,
    "message": message,
    "run_url": f"https://github.com/{repository}/actions/runs/{run_id}",
    "updated_at": datetime.now(timezone.utc).isoformat()
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, separators=(",", ":"))
PY

# Upload each status as an immutable snapshot. This avoids the brief BlobNotFound
# window caused by `gh release upload --clobber` deleting and recreating one asset.
gh release upload "$INBOX_TAG" "$STATUS_FILE" >/dev/null

# Keep a legacy exact-name copy for older Next Signer builds. Failure here must not
# affect the real signing job because current builds read the immutable snapshots.
LEGACY_FILE="$RUNNER_TEMP/status-$REQUEST_ID.json"
cp "$STATUS_FILE" "$LEGACY_FILE"
gh release upload "$INBOX_TAG" "$LEGACY_FILE" --clobber >/dev/null 2>&1 || true
