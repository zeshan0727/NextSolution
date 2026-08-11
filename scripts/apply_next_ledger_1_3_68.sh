#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_67.sh
python3 scripts/relax_fixed_liability_summary_anchor_1_3_68.py
python3 scripts/fix_fixed_liability_settlement_1_3_68.py
# clean authoritative 1.3.68 liability-settlement trigger
