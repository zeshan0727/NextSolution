#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_73.sh
python3 scripts/fix_ai_settings_1_3_74.py
# authoritative Next Ledger 1.3.74 AI privacy and settings cleanup build
