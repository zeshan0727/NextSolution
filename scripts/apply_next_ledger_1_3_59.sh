#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_58.sh
python3 scripts/fix_sms_latest15_review_pipeline_1_3_59.py
