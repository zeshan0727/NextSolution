from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "DailyLedger/Views/ReportsView.swift"
text = path.read_text(encoding="utf-8")

old = '''    private var interval: DateInterval {
        DateInterval(start: Calendar.current.startOfDay(for: start),
            end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))!)
    }
    private var natures: [AccountNature] {
'''
new = '''    private var interval: DateInterval {
        let startDay = Calendar.current.startOfDay(for: start)
        let endDay = Calendar.current.startOfDay(for: end)
        let endExclusive = Calendar.current.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        return DateInterval(start: startDay, end: endExclusive)
    }
    private var natures: [AccountNature] {
'''
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one Account Nature interval anchor, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Prepared unique Sample C report anchors.")
