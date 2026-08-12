#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_75.sh
python3 scripts/fix_sms_console_cleanup_1_3_76.py
# authoritative Next Ledger 1.3.76 SMS console cleanup build
