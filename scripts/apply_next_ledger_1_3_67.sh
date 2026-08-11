#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_66.sh
python3 scripts/fix_fixed_asset_register_link_date_export_1_3_67.py
# authoritative 1.3.67 trigger
