#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_74.sh
python3 scripts/fix_sms_ai_modern_ui_1_3_75.py
# authoritative Next Ledger 1.3.75 SMS AI controls and modern AI settings build
