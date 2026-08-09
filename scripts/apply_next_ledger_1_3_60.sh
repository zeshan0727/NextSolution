#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_59.sh
python3 scripts/fix_financial_summary_cashflow_1_3_60.py
