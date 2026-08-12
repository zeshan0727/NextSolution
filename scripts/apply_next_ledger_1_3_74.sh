#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_73.sh
python3 scripts/fix_sms_low_power_no_auto_ai_1_3_74.py
python3 scripts/fix_sms_no_ai_unused_1_3_74.py
# authoritative low-power SMS build trigger - final daemon compile
