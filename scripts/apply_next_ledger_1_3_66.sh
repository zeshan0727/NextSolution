#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_65.sh
python3 scripts/add_fixed_asset_liability_registers_1_3_66.py
# authoritative accounting-register build
