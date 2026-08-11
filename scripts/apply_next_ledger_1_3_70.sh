#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_69.sh
python3 scripts/fix_financial_summary_currency_drilldown_1_3_70.py
