from pathlib import Path
import sys

# Python automatically imports this module from the scripts directory.
# Only prepare the already-correct draft counter when the final SMS cleanup patch runs.
if Path(sys.argv[0]).name == "fix_sms_draft_fields_and_message_decoding.py":
    path = Path(__file__).resolve().parents[1] / "DailyLedger/Views/SMSImportConsoleView.swift"
    if path.exists():
        text = path.read_text(encoding="utf-8")
        old = 'Text("\\(draftCount)")'
        new = 'Text("\\\\(draftCount)")'
        if old in text and new not in text:
            path.write_text(text.replace(old, new, 1), encoding="utf-8")
