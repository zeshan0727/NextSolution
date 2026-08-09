#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_61.sh
python3 scripts/fix_sms_capture_first_1_3_62.py
