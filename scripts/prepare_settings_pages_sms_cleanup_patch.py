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

old_autosave = """console_text = console_text.replace(
    '''        .onAppear {
            configuration = SMSImportConsoleService.loadConfiguration()
            applySuggestedMappings()
            refresh()
        }
        .onReceive(timer) { _ in refresh() }
''',
    '''        .onAppear {
            loadingConfiguration = true
            configuration = SMSImportConsoleService.loadConfiguration()
            applySuggestedMappings()
            loadingConfiguration = false
            persistConfigurationSilently()
            refresh()
        }
        .onChange(of: configuration) { _ in
            guard !loadingConfiguration else { return }
            persistConfigurationSilently()
        }
        .onReceive(timer) { _ in refresh() }
''',
    1,
)
"""
new_autosave = """autosave_pattern = re.compile(
    r'''(?s)(        \\.onAppear \\{\\n.*?            refresh\\(\\)\\n        \\}\\n)(        \\.onReceive\\(timer\\) \\{ _ in refresh\\(\\) \\}\\n)'''
)
autosave_replacement = r'''        .onAppear {
            loadingConfiguration = true
            configuration = SMSImportConsoleService.loadConfiguration()
            applySuggestedMappings()
            loadingConfiguration = false
            persistConfigurationSilently()
            refresh()
        }
        .onChange(of: configuration) { _ in
            guard !loadingConfiguration else { return }
            persistConfigurationSilently()
        }
        .onReceive(timer) { _ in refresh() }
'''
console_text, autosave_count = autosave_pattern.subn(autosave_replacement, console_text, count=1)
if autosave_count != 1:
    raise RuntimeError(f"Expected one SMS settings lifecycle block, found {autosave_count}")
"""
count = text.count(old_autosave)
if count != 1:
    raise RuntimeError(f"Expected one old SMS auto-save source block, found {count}")
text = text.replace(old_autosave, new_autosave, 1)

old_destination = """    '''static NSString *CashDestinationAccountID(NSDictionary *config, NSDictionary *ledger) {
    NSArray *accounts = ledger[@\"accounts\"] ?: @[];
    NSString *configured = config[@\"cashAccountID\"];
    if (AccountExists(accounts, configured)) return configured;
    return AccountIDByName(accounts, @[@\"cash\"]);
}

static NSString *CategoryForVendor(NSDictionary *ledger, NSString *vendor) {
''',
)
"""
new_destination = """    '''static NSString *CashDestinationAccountID(NSDictionary *config, NSDictionary *ledger) {
    NSArray *accounts = ledger[@\"accounts\"] ?: @[];
    NSString *configured = config[@\"cashAccountID\"];
    if (AccountExists(accounts, configured)) return configured;
    return AccountIDByName(accounts, @[@\"cash\"]);
}

''',
)
"""
count = text.count(old_destination)
if count != 1:
    raise RuntimeError(f"Expected one duplicate CategoryForVendor source block, found {count}")
text = text.replace(old_destination, new_destination, 1)

loan_reference_cleanup = r'''

# Remove stale draft-approval references after the Loan Payment setting is retired.
for swift_path in [
    "DailyLedger/Services/LedgerStore.swift",
    "DailyLedger/Views/SMSDraftInboxView.swift",
]:
    generated = read(swift_path)
    stale_count = generated.count("configuration.loanPaymentAccountID")
    if stale_count > 0:
        generated = generated.replace(
            "configuration.loanPaymentAccountID",
            "(nil as String?)"
        )
        write(swift_path, generated)
'''
if "# Remove stale draft-approval references after the Loan Payment setting is retired." not in text:
    text += loan_reference_cleanup

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
print("Prepared stable SMS state, auto-save, daemon functions, and retired Loan Payment references.")
