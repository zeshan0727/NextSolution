#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/adjust_build_v144.py"
python3 "$SCRIPT_DIR/adjust_build_v145.py"
chmod +x "$SCRIPT_DIR/build-v143.sh"
exec "$SCRIPT_DIR/build-v143.sh"
