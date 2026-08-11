#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_72.sh
python3 scripts/fix_sms_scheduled_daemon_1_3_73.py
