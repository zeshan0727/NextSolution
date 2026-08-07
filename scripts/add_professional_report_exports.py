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
runpy.run_path(
    str(ROOT / "scripts/prepare_sample_c_report_anchors.py"),
    run_name="__main__",
)
runpy.run_path(
    str(ROOT / "scripts/apply_sample_c_screen_matched_exports.py"),
    run_name="__main__",
)

# Final SMS safety layer. This runs after all earlier SMS parser patches so
# approved-bank messages that are still unknown become editable review drafts.
# It also recognizes account-debit Card Payment messages such as CUR1 as
# transfer review drafts rather than dropping them.
runpy.run_path(
    str(ROOT / "scripts/add_sms_unrecognized_review_fallback.py"),
    run_name="__main__",
)
runpy.run_path(
    str(ROOT / "scripts/add_sms_fallback_selftest.py"),
    run_name="__main__",
)

# Keep the established daemon package version for the repair layer; the 1.3.51
# realtime patch bumps it to 2.1.8 after this script completes.
replace_once(
    "RootHideSMSQueue/Sources/main.m",
    'static NSString *const kDaemonVersion = @"2.1.7";',
    'static NSString *const kDaemonVersion = @"2.1.6";',
)
replace_once("RootHideSMSQueue/control", "Version: 2.1.7", "Version: 2.1.6")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    replace_once(
        path,
        "Next Ledger SMS Daemon 2.1.7 installation started",
        "Next Ledger SMS Daemon 2.1.6 installation started",
    )

# Stabilize the final 1.3.51 patch against generated nested Swift views before
# the workflow executes it on the next line.
runpy.run_path(
    str(ROOT / "scripts/prepare_sms_realtime_ai_patch.py"),
    run_name="__main__",
)

print("Added professional reports plus fail-safe editable SMS transfer review.")
