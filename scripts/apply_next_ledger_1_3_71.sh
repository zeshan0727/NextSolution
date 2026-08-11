#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_70.sh
python3 scripts/add_developer_lab_1_3_71.py
# authoritative 1.3.71 Developer Lab build
