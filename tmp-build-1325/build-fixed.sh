#!/bin/bash
set -euo pipefail
cp tmp-build-1325/build.sh "$RUNNER_TEMP/build-1325-real.sh"
sed -i '' 's/-p3 /-p4 /g' "$RUNNER_TEMP/build-1325-real.sh"
exec bash "$RUNNER_TEMP/build-1325-real.sh"
