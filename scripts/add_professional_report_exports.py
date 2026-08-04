from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def write(relative: str, content: str) -> None:
    (ROOT / relative).write_text(content, encoding="utf-8")


def replace_once(relative: str, old: str, new: str) -> None:
    text = read(relative)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {relative}, found {count}: {old[:180]!r}")
    write(relative, text.replace(old, new, 1))


replace_once(
    "DailyLedger/Views/ReportsView.swift",
    '''                Section("Planning & Comparison") {
                    NavigationLink { ChartOfAccountsView() } label: {
''',
    '''                Section("Planning & Comparison") {
                    NavigationLink { ProfessionalReportExportView() } label: {
                        Label("Export PDF & Excel Reports", systemImage: "doc.badge.arrow.up.fill")
                    }
                    NavigationLink { ChartOfAccountsView() } label: {
''',
)

runpy.run_path(
    str(ROOT / "scripts/fix_professional_report_export_compile.py"),
    run_name="__main__",
)
runpy.run_path(
    str(ROOT / "scripts/add_report_downloads_and_qar_consolidation.py"),
    run_name="__main__",
)

print("Added professional reports, per-report downloads, and QAR/PKR consolidation.")
