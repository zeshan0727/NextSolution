#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_55.sh
python3 scripts/auto_use_existing_openai_for_sms_1_3_56.py
