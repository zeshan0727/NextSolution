#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_60.sh
python3 scripts/fix_sms_capture_history_ai_1_3_61.py
