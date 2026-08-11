from pathlib import Path

path = Path(__file__).resolve().parents[1] / "DailyLedger/Services/ERPAccountingEngine.swift"
text = path.read_text(encoding="utf-8")
anchor = '''    func erpReportLineValue(_ line: ERPReportLineDefinition, interval: DateInterval, currencyCode requestedCurrency: String) -> Decimal {'''
if anchor not in text:
    raise SystemExit("ERP report-line value anchor missing")
# Keep the primary implementation and expose a descriptive alias used by build validation
# and future custom-report callers.
insert = '''    func erpCustomReportLineValue(_ line: ERPReportLineDefinition, interval: DateInterval, currencyCode requestedCurrency: String) -> Decimal {
        erpReportLineValue(line, interval: interval, currencyCode: requestedCurrency)
    }

'''
if 'func erpCustomReportLineValue(' not in text:
    text = text.replace(anchor, insert + anchor, 1)
path.write_text(text, encoding="utf-8")
print("Added ERP custom report-line value alias.")
