#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_57.sh
python3 scripts/fix_sms_ai_loop_1_3_58.py
