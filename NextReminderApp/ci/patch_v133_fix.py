#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "NextReminder" / "Sources" / "XPostGenerator.swift"
text = path.read_text()

broken = '''            : "Do not repeat these recently generated GTA angles:
" + excludedAngles.map { "- \($0)" }.joined(separator: "
")'''

fixed = r'''            : "Do not repeat these recently generated GTA angles:\n" + excludedAngles.map { "- \($0)" }.joined(separator: "\n")'''

if broken not in text:
    raise SystemExit("Expected generated GTA exclusion string was not found")

path.write_text(text.replace(broken, fixed, 1))
print("Next Reminder v1.3.3 GTA exclusion string fixed successfully.")
