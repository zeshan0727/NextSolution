from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

source_path = ROOT / "RootHideSMSQueue/Sources/main.m"
source = source_path.read_text(encoding="utf-8")
old = "static NSString *SMSDatabaseDiagnostics(void) {"
new = "__attribute__((unused)) static NSString *SMSDatabaseDiagnostics(void) {"
count = source.count(old)
if count != 1:
    raise RuntimeError(f"Expected one SMSDatabaseDiagnostics helper, found {count}")
source_path.write_text(source.replace(old, new, 1), encoding="utf-8")

# The old SMS-import cleanup removes showingSMSStatus. Recreate it only as a
# stable one-line anchor for the final compact-AI patch that follows this file.
settings_path = ROOT / "DailyLedger/Views/SettingsView.swift"
settings = settings_path.read_text(encoding="utf-8")
visual_theme = '    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = AppVisualTheme.glass.rawValue\n'
anchor = visual_theme + '    @State private var showingSMSStatus = true\n'
if settings.count(visual_theme) != 1:
    raise RuntimeError("Expected one DailyLedgerVisualTheme setting")
if '    @State private var showingSMSStatus = true\n' not in settings:
    settings = settings.replace(visual_theme, anchor, 1)
settings_path.write_text(settings, encoding="utf-8")

print("Marked the retained database helper unused and prepared the compact-AI state anchor.")
