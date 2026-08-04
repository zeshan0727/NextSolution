#!/usr/bin/env python3
from pathlib import Path
import runpy

root = Path(__file__).resolve().parents[1]
workflow = root / ".github/workflows/build-tipa.yml"
workflow_before = workflow.read_text(encoding="utf-8")

runpy.run_path(str(root / "scripts/apply_next_ledger_1_3_37.py"), run_name="__main__")

# The workflow is versioned directly through the GitHub connector. Keep the
# generated commit limited to app source and project metadata so Actions can
# push it using the standard contents permission.
workflow.write_text(workflow_before, encoding="utf-8")
print("Preserved workflow file; source migration is ready to commit.")
