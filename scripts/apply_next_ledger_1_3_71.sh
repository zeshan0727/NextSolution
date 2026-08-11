#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_70.sh
python3 scripts/repair_developer_lab_patcher_1_3_71.py
python3 scripts/add_developer_lab_1_3_71.py
# corrected validation build trigger
