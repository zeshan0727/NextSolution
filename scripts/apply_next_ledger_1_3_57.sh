#!/bin/bash
set -euo pipefail
bash scripts/apply_next_ledger_1_3_56.sh
python3 scripts/fix_openai_save_and_autolink_1_3_57.py
