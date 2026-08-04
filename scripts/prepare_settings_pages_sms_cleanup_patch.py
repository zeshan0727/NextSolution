from pathlib import Path

path = Path(__file__).resolve().parent / "add_settings_pages_custom_sms_and_log_cleanup.py"
text = path.read_text(encoding="utf-8")
old = '''replace_once(
    console,
    ''' + "'''" + '''    @State private var snapshot = SMSImportConsoleSnapshot()\n    @State private var notice: String?\n''' + "'''" + ''',
    ''' + "'''" + '''    @State private var snapshot = SMSImportConsoleSnapshot()\n    @State private var notice: String?\n    @State private var loadingConfiguration = true\n''' + "'''" + ''',
)
'''
new = '''replace_once(
    console,
    ''' + "'''" + '''    @State private var notice: String?\n''' + "'''" + ''',
    ''' + "'''" + '''    @State private var notice: String?\n    @State private var loadingConfiguration = true\n''' + "'''" + ''',
)
'''
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one SMS state-anchor patch, found {count}")
text = text.replace(old, new, 1)

diagnostics = r'''

# Build-time diagnostics for strict workflow assertions.
for generated_path, needles in {
    "RootHideSMSQueue/Sources/main.m": [
        'kind = @"billPayment"',
        "loan payment transfer",
        "customEnding",
        "ApplyMaintenanceRequests",
    ],
    "DailyLedger/Services/SMSImportConsoleService.swift": [
        "loanPaymentAccountID",
        'var customEnding = ""',
        "var customAccountID: String?",
    ],
    "DailyLedger/Views/SMSImportConsoleView.swift": [
        "Loan Payment Account",
        'TextField("Custom card/account ending"',
        "SMSImportLogsView",
        ".onChange(of: configuration)",
    ],
    "DailyLedger/Views/SettingsView.swift": [
        "SettingsSectionPage(title:",
        "DisclosureGroup(isExpanded: settingsSectionBinding",
        "expandedSettingsSection",
    ],
}.items():
    generated = read(generated_path)
    print(f"VALIDATION {generated_path}")
    for needle in needles:
        print(f"  {needle!r}: {generated.count(needle)}")
'''
if "# Build-time diagnostics for strict workflow assertions." not in text:
    text += diagnostics

path.write_text(text, encoding="utf-8")
print("Prepared the SMS console patch with a diagnostics-independent state anchor and explicit validation counts.")
