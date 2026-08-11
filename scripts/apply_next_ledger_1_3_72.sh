#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_71.sh
python3 scripts/materialize_erp_1_3_72.py
python3 scripts/materialize_erp_patcher_1_3_72.py
python3 scripts/add_erp_accounting_center_1_3_72.py
python3 scripts/fix_erp_alias_1_3_72.py
python3 scripts/fix_erp_report_label_1_3_72.py
# authoritative 1.3.72 ERP accounting build trigger - Xcode compile
