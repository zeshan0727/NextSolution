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

STATUS_FILE="$RUNNER_TEMP/status-$REQUEST_ID.json"
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

gh release upload "$INBOX_TAG" "$STATUS_FILE" --clobber >/dev/null
