#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
reports = ROOT / "DailyLedger/Views/ReportsView.swift"
text = reports.read_text(encoding="utf-8")

card_pattern = re.compile(r'''\n\s*ReportTotalCard\(\n\s*title: "Carried Forward Balance",.*?\n\s*\)\n''', re.S)
text, card_count = card_pattern.subn("\n", text, count=1)
if card_count == 0 and "Carried Forward Balance" in text:
    raise RuntimeError("Could not remove carried-forward card")

logic_pattern = re.compile(r'''\n\s*private var openingBalance: Decimal \{.*?\n\s*private var convertedLoanMovement: Decimal \{''', re.S)
replacement = '''

    private var financeSummaryNetBalance: Decimal {
        totals.income + convertedLoanMovement - totals.expense
    }

    private var convertedLoanMovement: Decimal {'''
text, logic_count = logic_pattern.subn(replacement, text, count=1)
if logic_count == 0:
    if "private var carriedForwardBalance" in text or "private var openingBalance" in text:
        raise RuntimeError("Could not remove carried-forward calculation")
    if "totals.income + convertedLoanMovement - totals.expense" not in text:
        raise RuntimeError("Expected 1.3.37 finance summary formula is missing")

reports.write_text(text, encoding="utf-8")

project = ROOT / "project.yml"
project_text = project.read_text(encoding="utf-8")
project_text = project_text.replace('MARKETING_VERSION: "1.3.38"', 'MARKETING_VERSION: "1.3.39"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "46"', 'CURRENT_PROJECT_VERSION: "47"')
project.write_text(project_text, encoding="utf-8")

print("Removed carried-forward balance and restored the 1.3.37 finance-summary formula.")
