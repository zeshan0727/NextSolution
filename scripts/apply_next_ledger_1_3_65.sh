#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_64.sh
python3 scripts/fix_transaction_update_colors_1_3_65.py
