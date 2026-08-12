#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_73.sh
python3 scripts/fix_sms_low_power_no_auto_ai_1_3_74.py
