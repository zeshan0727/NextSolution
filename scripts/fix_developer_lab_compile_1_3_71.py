from pathlib import Path

reports = Path("DailyLedger/Views/ReportsView.swift")
text = reports.read_text()
bad = "private func convertedMovementTotal    private func convertedMovementTotal("
if bad not in text:
    raise SystemExit("duplicated convertedMovementTotal compiler anchor not found")
text = text.replace(bad, "private func convertedMovementTotal(", 1)
reports.write_text(text)

lab = Path("DailyLedger/Views/DeveloperLabView.swift")
text = lab.read_text()
text = text.replace("ChartLegend(color:", "DeveloperChartLegend(color:")
anchor = "struct DeveloperActivityChart: View {\n"
if anchor not in text:
    raise SystemExit("DeveloperActivityChart anchor not found")
legend = '''private struct DeveloperChartLegend: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

'''
if "private struct DeveloperChartLegend: View" not in text:
    text = text.replace(anchor, legend + anchor, 1)
lab.write_text(text)

print("Fixed 1.3.71 generated report function boundary and added a Developer Lab-local chart legend.")
