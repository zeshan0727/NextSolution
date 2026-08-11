#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_63.sh
python3 scripts/fix_balance_nature_report_preview_1_3_64.py
python3 scripts/fix_next_ledger_1_3_64_compile.py
# authoritative corrected build
