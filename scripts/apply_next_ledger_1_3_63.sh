#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_62.sh
python3 scripts/fix_sms_review_manual_ai_1_3_63.py
# authoritative build trigger 2
