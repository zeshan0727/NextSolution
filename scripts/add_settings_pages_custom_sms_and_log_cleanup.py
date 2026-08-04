from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:240]!r}")
    write(path, text.replace(old, new, 1))


def replace_range(path: str, start: str, end: str, replacement: str) -> None:
    text = read(path)
    start_index = text.find(start)
    if start_index < 0:
        raise RuntimeError(f"Start marker missing in {path}: {start!r}")
    end_index = text.find(end, start_index)
    if end_index < 0:
        raise RuntimeError(f"End marker missing in {path}: {end!r}")
    write(path, text[:start_index] + replacement + text[end_index:])


def matching_brace(text: str, opening: int) -> int:
    depth = 0
    in_string = False
    escaped = False
    index = opening
    while index < len(text):
        character = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
        else:
            if character == '"':
                in_string = True
            elif character == "{":
                depth += 1
            elif character == "}":
                depth -= 1
                if depth == 0:
                    return index
        index += 1
    raise RuntimeError("Unbalanced Swift braces")


# ---------------------------------------------------------------------------
# Persistent SMS configuration: remove the unused Loan Payment mapping and add
# one user-controlled custom card/account ending plus a daemon log-clear request.
# Unknown legacy JSON keys remain harmless and all retained values migrate.
# ---------------------------------------------------------------------------
service = "DailyLedger/Services/SMSImportConsoleService.swift"
replace_once(
    service,
    '''    var cashAccountID: String?
    var loanPaymentAccountID: String?
    var approvedSenders: [String] = ["Cb SMS"]
''',
    '''    var cashAccountID: String?
    var customEnding = ""
    var customAccountID: String?
    var clearLogsRequestID = 0
    var approvedSenders: [String] = ["Cb SMS"]
''',
)
replace_once(
    service,
    '''        case cashAccountID
        case loanPaymentAccountID
        case approvedSenders
''',
    '''        case cashAccountID
        case customEnding
        case customAccountID
        case clearLogsRequestID
        case approvedSenders
''',
)
replace_once(
    service,
    '''        cashAccountID = try container.decodeIfPresent(String.self, forKey: .cashAccountID)
        loanPaymentAccountID = try container.decodeIfPresent(String.self, forKey: .loanPaymentAccountID)
        approvedSenders = try container.decodeIfPresent([String].self, forKey: .approvedSenders) ?? ["Cb SMS"]
''',
    '''        cashAccountID = try container.decodeIfPresent(String.self, forKey: .cashAccountID)
        customEnding = try container.decodeIfPresent(String.self, forKey: .customEnding) ?? ""
        customAccountID = try container.decodeIfPresent(String.self, forKey: .customAccountID)
        clearLogsRequestID = try container.decodeIfPresent(Int.self, forKey: .clearLogsRequestID) ?? 0
        approvedSenders = try container.decodeIfPresent([String].self, forKey: .approvedSenders) ?? ["Cb SMS"]
''',
)

service_text = read(service)
service_text = service_text.replace(
    '        case "withdrawal", "billPayment", "incomingTransfer": return .transfer',
    '        case "withdrawal", "incomingTransfer": return .transfer',
)
service_text = re.sub(
    r'''(?m)^        case "billPayment":\n            pattern = .*?\n''',
    "",
    service_text,
    count=1,
)
write(service, service_text)


# ---------------------------------------------------------------------------
# SMS settings UI: persistent automatic saves, a custom mapping, no Loan Payment
# field, and detailed logs moved to a separate final page with Clear Logs.
# ---------------------------------------------------------------------------
console = "DailyLedger/Views/SMSImportConsoleView.swift"
replace_once(
    console,
    '''    @State private var snapshot = SMSImportConsoleSnapshot()
    @State private var notice: String?
''',
    '''    @State private var snapshot = SMSImportConsoleSnapshot()
    @State private var notice: String?
    @State private var loadingConfiguration = true
''',
)
replace_once(
    console,
    '''                accountPicker(
                    title: "Loan Payment Account",
                    selection: optionalBinding(
                        get: { configuration.loanPaymentAccountID },
                        set: { configuration.loanPaymentAccountID = $0 }
                    ),
                    suggestedWords: ["loan", "payment"]
                )
''',
    '''                TextField("Custom card/account ending", text: customEndingBinding)
                    .keyboardType(.numberPad)
                accountPicker(
                    title: "Custom Account",
                    selection: optionalBinding(
                        get: { configuration.customAccountID },
                        set: { configuration.customAccountID = $0 }
                    ),
                    suggestedWords: []
                )
''',
)

console_text = read(console)
console_text = re.sub(
    r'''(?s)        if configuration\.loanPaymentAccountID == nil,\n.*?            configuration\.loanPaymentAccountID = account\.id\.uuidString\n        \}\n''',
    "",
    console_text,
    count=1,
)
console_text = console_text.replace(
    'Text("**6760 purchases become expenses, cashback becomes refund income, **0023 withdrawals transfer to Cash, and bill payments transfer to the Loan Payment account.")',
    'Text("Cards, cash and custom mapping")',
)
console_text = console_text.replace(
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

save_marker = '''    private func saveConfiguration(requestScan: Bool) {
'''
custom_helpers = r'''    private var customEndingBinding: Binding<String> {
        Binding(
            get: { configuration.customEnding },
            set: { value in
                configuration.customEnding = String(value.filter(\.isNumber).suffix(8))
            }
        )
    }

    private func persistConfigurationSilently() {
        try? SMSImportConsoleService.saveConfiguration(configuration)
    }

'''
if save_marker not in console_text:
    raise RuntimeError("SMS saveConfiguration marker not found")
console_text = console_text.replace(save_marker, custom_helpers + save_marker, 1)

log_start = console_text.find('            Section {\n                if snapshot.logs.isEmpty {')
log_end_marker = '        }\n        .navigationTitle("SMS Import Console")'
log_end = console_text.find(log_end_marker, log_start)
if log_start < 0 or log_end < 0:
    raise RuntimeError("SMS log section markers not found")
log_link = '''            Section {
                NavigationLink {
                    SMSImportLogsView()
                } label: {
                    HStack {
                        Label("Logs", systemImage: "doc.text.magnifyingglass")
                        Spacer()
                        Text("\\(snapshot.logs.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
'''
console_text = console_text[:log_start] + log_link + console_text[log_end:]

logs_view = r'''

private struct SMSImportLogsView: View {
    @State private var snapshot = SMSImportConsoleSnapshot()
    @State private var notice: String?

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            if snapshot.logs.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        Text("No logs")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } else {
                Section {
                    ForEach(snapshot.logs.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.level.uppercased())
                                    .font(.caption2.bold())
                                Spacer()
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            Section {
                Button("Clear Logs", role: .destructive) {
                    clearLogs()
                }
            }
        }
        .navigationTitle("SMS Logs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
        .alert("SMS Logs", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private func refresh() {
        snapshot = SMSImportConsoleService.loadSnapshot()
    }

    private func clearLogs() {
        var configuration = SMSImportConsoleService.loadConfiguration()
        configuration.clearLogsRequestID += 1
        do {
            try SMSImportConsoleService.saveConfiguration(configuration)
            notice = "Log cleanup requested."
        } catch {
            notice = "Logs could not be cleared."
        }
    }
}
'''
console_text = console_text.rstrip() + logs_view
write(console, console_text)


# ---------------------------------------------------------------------------
# Daemon 2.1.6: custom account mapping, log cleanup/cap, and removal of the
# unsupported Loan Payment parser/import path.
# ---------------------------------------------------------------------------
source = "RootHideSMSQueue/Sources/main.m"
replace_once(source, 'static NSString *const kDaemonVersion = @"2.1.5";', 'static NSString *const kDaemonVersion = @"2.1.6";')
replace_once(source, '    while (logs.count > 100) [logs removeObjectAtIndex:0];', '    while (logs.count > 40) [logs removeObjectAtIndex:0];')
replace_once(
    source,
    '''        @"autoRecord": @NO,
        @"cardAccountIDs": @{},
''',
    '''        @"autoRecord": @NO,
        @"customEnding": @"",
        @"customAccountID": @"",
        @"clearLogsRequestID": @0,
        @"cardAccountIDs": @{},
''',
)
replace_once(
    source,
    '''    else if ([lower containsString:@"bill payment"] && [lower containsString:@"from card"]) kind = @"billPayment";
''',
    "",
)
source_text = read(source)
source_text = re.sub(
    r'''(?s)    \} else if \(\[kind isEqualToString:@"billPayment"\]\) \{\n        vendor = .*?;\n''',
    "",
    source_text,
    count=1,
)
source_text = source_text.replace(
    '[lower containsString:@"bill payment"] || ',
    '',
)
write(source, source_text)

replace_once(
    source,
    '''static BOOL CardEndingApproved(NSDictionary *config, NSString *ending) {
    NSDictionary *mappings = [config[@"cardAccountIDs"] isKindOfClass:NSDictionary.class]
        ? config[@"cardAccountIDs"] : @{};
    if (mappings.count > 0) return mappings[ending] != nil;
    return [@[@"6760", @"0023"] containsObject:ending];
}
''',
    '''static BOOL CardEndingApproved(NSDictionary *config, NSString *ending) {
    NSString *customEnding = [config[@"customEnding"] isKindOfClass:NSString.class]
        ? config[@"customEnding"] : @"";
    NSString *customAccountID = [config[@"customAccountID"] isKindOfClass:NSString.class]
        ? config[@"customAccountID"] : @"";
    if (customEnding.length > 0 && customAccountID.length > 0 && [customEnding isEqualToString:ending]) {
        return YES;
    }
    NSDictionary *mappings = [config[@"cardAccountIDs"] isKindOfClass:NSDictionary.class]
        ? config[@"cardAccountIDs"] : @{};
    if (mappings.count > 0) return mappings[ending] != nil;
    return [@[@"6760", @"0023"] containsObject:ending];
}
''',
)
replace_once(
    source,
    '''    NSString *configured = [config[@"cardAccountIDs"] isKindOfClass:NSDictionary.class] ? config[@"cardAccountIDs"][ending] : nil;
    if (AccountExists(accounts, configured)) return configured;
''',
    '''    NSString *configured = [config[@"cardAccountIDs"] isKindOfClass:NSDictionary.class] ? config[@"cardAccountIDs"][ending] : nil;
    if (AccountExists(accounts, configured)) return configured;
    NSString *customEnding = [config[@"customEnding"] isKindOfClass:NSString.class] ? config[@"customEnding"] : @"";
    NSString *customAccountID = [config[@"customAccountID"] isKindOfClass:NSString.class] ? config[@"customAccountID"] : @"";
    if ([customEnding isEqualToString:ending] && AccountExists(accounts, customAccountID)) return customAccountID;
''',
)
replace_range(
    source,
    'static NSString *DestinationAccountID(NSDictionary *config, NSDictionary *ledger, NSString *kind) {\n',
    'static NSString *CategoryForVendor(NSDictionary *ledger, NSString *vendor) {\n',
    '''static NSString *CashDestinationAccountID(NSDictionary *config, NSDictionary *ledger) {
    NSArray *accounts = ledger[@"accounts"] ?: @[];
    NSString *configured = config[@"cashAccountID"];
    if (AccountExists(accounts, configured)) return configured;
    return AccountIDByName(accounts, @[@"cash"]);
}

static NSString *CategoryForVendor(NSDictionary *ledger, NSString *vendor) {
''',
)
replace_once(
    source,
    '''        if ([kind isEqualToString:@"withdrawal"] || [kind isEqualToString:@"billPayment"]) {
            NSString *destination = DestinationAccountID(config, ledger, kind);
            if (!destination) {
                AddLog(@"warning", @"Waiting for %@ destination account mapping.", [kind isEqualToString:@"withdrawal"] ? @"Cash" : @"Loan Payment");
                result = ImportResultWaitingForMapping;
                @throw [NSException exceptionWithName:@"Mapping" reason:nil userInfo:nil];
            }
            transaction[@"type"] = @"transfer";
            transaction[@"category"] = @"Transfer";
            transaction[@"destinationAccountID"] = destination;
            transaction[@"destinationAmount"] = event[@"amount"];
''',
    '''        if ([kind isEqualToString:@"withdrawal"]) {
            NSString *destination = CashDestinationAccountID(config, ledger);
            if (!destination) {
                AddLog(@"warning", @"Waiting for Cash destination account mapping.");
                result = ImportResultWaitingForMapping;
                @throw [NSException exceptionWithName:@"Mapping" reason:nil userInfo:nil];
            }
            transaction[@"type"] = @"transfer";
            transaction[@"category"] = @"Transfer";
            transaction[@"destinationAccountID"] = destination;
            transaction[@"destinationAmount"] = event[@"amount"];
''',
)

source_text = read(source)
loan_test_pattern = re.compile(
    r'''(?s)        @\{\n            @"name": @"loan payment transfer",.*?\n        \},\n'''
)
source_text, removed = loan_test_pattern.subn("", source_text, count=1)
if removed != 1:
    raise RuntimeError(f"Expected one Loan Payment self-test, removed {removed}")
write(source, source_text)

maintenance = r'''static void ApplyMaintenanceRequests(NSDictionary *config) {
    NSInteger requested = [config[@"clearLogsRequestID"] integerValue];
    NSInteger completed = [gState[@"lastClearLogsRequestID"] integerValue];
    if (requested == completed) return;
    gState[@"logs"] = [NSMutableArray array];
    gState[@"lastClearLogsRequestID"] = @(requested);
    SaveState();
    WriteConsole(@"Logs cleared.");
}

'''
replace_once(
    source,
    '''static NSInteger ConfiguredAutomaticScanHours(NSDictionary *config) {
''',
    maintenance + '''static NSInteger ConfiguredAutomaticScanHours(NSDictionary *config) {
''',
)
replace_once(
    source,
    '''static void ScanMessages(BOOL forceRecent) {
    NSDictionary *config = LoadConfiguration();
''',
    '''static void ScanMessages(BOOL forceRecent) {
    NSDictionary *config = LoadConfiguration();
    ApplyMaintenanceRequests(config);
''',
)

for path in ["RootHideSMSQueue/control"]:
    replace_once(path, "Version: 2.1.5", "Version: 2.1.6")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    replace_once(
        path,
        "Next Ledger SMS Daemon 2.1.5 installation started",
        "Next Ledger SMS Daemon 2.1.6 installation started",
    )


# ---------------------------------------------------------------------------
# Settings: replace every generated expanding top-level section with a normal
# NavigationLink that opens its controls on a dedicated page.
# ---------------------------------------------------------------------------
settings = "DailyLedger/Views/SettingsView.swift"
settings_text = read(settings)
settings_text = settings_text.replace('    @State private var expandedSettingsSection: String?\n', '', 1)
settings_text = settings_text.replace('    @State private var showingAISettings = false\n', '', 1)
settings_text = re.sub(
    r'''(?s)    private func settingsSectionBinding\(_ title: String\) -> Binding<Bool> \{.*?\n    \}\n\n''',
    "",
    settings_text,
    count=1,
)

list_marker = "            List {"
list_start = settings_text.find(list_marker)
if list_start < 0:
    raise RuntimeError("Settings List marker not found")
list_open = settings_text.find("{", list_start)
list_close = matching_brace(settings_text, list_open)
body = settings_text[list_open + 1:list_close]
section_starts = [match.start() for match in re.finditer(r'(?m)^                Section\s*\{', body)]
replacements = []
converted = 0
for position, start in enumerate(section_starts):
    end = section_starts[position + 1] if position + 1 < len(section_starts) else len(body)
    chunk = body[start:end]
    disclosure_match = re.search(r'DisclosureGroup\(isExpanded: settingsSectionBinding\("([^"]+)"\)\)', chunk)
    if not disclosure_match:
        continue
    title = disclosure_match.group(1)
    disclosure_open = chunk.find("{", disclosure_match.end())
    disclosure_close = matching_brace(chunk, disclosure_open)
    content = chunk[disclosure_open + 1:disclosure_close].rstrip()
    label_tail = chunk[disclosure_close + 1:]
    icon_match = re.search(r'Label\("[^"]+",\s*systemImage:\s*"([^"]+)"\)', label_tail, re.S)
    icon = icon_match.group(1) if icon_match else "gearshape.fill"
    replacement = (
        '                Section {\n'
        '                    NavigationLink {\n'
        f'                        SettingsSectionPage(title: "{title}") {{'
        f'{content}\n'
        '                        }\n'
        '                    } label: {\n'
        f'                        Label("{title}", systemImage: "{icon}")\n'
        '                    }\n'
        '                }\n\n'
    )
    replacements.append((start, end, replacement))
    converted += 1

if converted < 5:
    raise RuntimeError(f"Expected at least five Settings pages, converted {converted}")
for start, end, replacement in reversed(replacements):
    body = body[:start] + replacement + body[end:]
settings_text = settings_text[:list_open + 1] + body + settings_text[list_close:]

page_view = r'''private struct SettingsSectionPage<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        List {
            Section {
                content
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

'''
page_marker = "private struct ImportDocumentPicker: UIViewControllerRepresentable {\n"
if page_marker not in settings_text:
    raise RuntimeError("Settings page insertion marker not found")
settings_text = settings_text.replace(page_marker, page_view + page_marker, 1)
write(settings, settings_text)

print("Added dedicated Settings pages, persistent custom SMS mapping, log cleanup, and removed Loan Payment SMS handling.")
