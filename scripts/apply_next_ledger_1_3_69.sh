#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_68.sh
python3 scripts/fix_fixed_liability_ledger_only_1_3_69.py
