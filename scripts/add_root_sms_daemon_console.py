from pathlib import Path

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
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:160]!r}")
    write(path, text.replace(old, new, 1))


service = r'''import Foundation

struct SMSImportConfiguration: Codable, Equatable {
    var enabled = true
    var cardAccountIDs: [String: String] = [:]
    var cashAccountID: String?
    var loanPaymentAccountID: String?
    var scanRequestID = 0
}

struct SMSImportLogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let level: String
    let message: String
}

struct SMSImportConsoleSnapshot: Codable, Equatable {
    var daemonRunning = false
    var lastHeartbeat: Date?
    var lastScanDate: Date?
    var lastImportDate: Date?
    var lastResult = "No daemon status received yet."
    var totalImported = 0
    var totalDuplicates = 0
    var totalParseFailures = 0
    var pendingCount = 0
    var logs: [SMSImportLogEntry] = []
}

enum SMSImportConsoleService {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func loadConfiguration() -> SMSImportConfiguration {
        guard let data = try? Data(contentsOf: configurationURL),
              let value = try? decoder.decode(SMSImportConfiguration.self, from: data) else {
            return SMSImportConfiguration()
        }
        return value
    }

    static func saveConfiguration(_ configuration: SMSImportConfiguration) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let data = try encoder.encode(configuration)
        try data.write(to: configurationURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: configurationURL.path
        )
    }

    static func loadSnapshot() -> SMSImportConsoleSnapshot {
        guard let data = try? Data(contentsOf: consoleURL),
              let value = try? decoder.decode(SMSImportConsoleSnapshot.self, from: data) else {
            return SMSImportConsoleSnapshot()
        }
        return value
    }

    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("DailyLedger", isDirectory: true)
    }

    static var configurationURL: URL {
        directoryURL.appendingPathComponent("sms-import-config.json")
    }

    static var consoleURL: URL {
        directoryURL.appendingPathComponent("sms-import-console.json")
    }
}
'''
write("DailyLedger/Services/SMSImportConsoleService.swift", service)

view = r'''import SwiftUI

struct SMSImportConsoleView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var configuration = SMSImportConfiguration()
    @State private var snapshot = SMSImportConsoleSnapshot()
    @State private var notice: String?

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                Toggle("Automatic Bank SMS Import", isOn: $configuration.enabled)
                accountPicker(
                    title: "Credit Card **6760",
                    selection: cardBinding("6760"),
                    suggestedWords: ["credit", "6760"]
                )
                accountPicker(
                    title: "Debit Card **0023",
                    selection: cardBinding("0023"),
                    suggestedWords: ["debit", "0023"]
                )
                accountPicker(
                    title: "Cash Account",
                    selection: optionalBinding(
                        get: { configuration.cashAccountID },
                        set: { configuration.cashAccountID = $0 }
                    ),
                    suggestedWords: ["cash"]
                )
                accountPicker(
                    title: "Loan Payment Account",
                    selection: optionalBinding(
                        get: { configuration.loanPaymentAccountID },
                        set: { configuration.loanPaymentAccountID = $0 }
                    ),
                    suggestedWords: ["loan", "payment"]
                )

                Button {
                    saveConfiguration(requestScan: false)
                } label: {
                    Label("Save Import Settings", systemImage: "checkmark.circle.fill")
                }

                Button {
                    saveConfiguration(requestScan: true)
                } label: {
                    Label("Scan Recent Messages", systemImage: "arrow.clockwise.circle.fill")
                }
            } header: {
                Label("Account Mapping", systemImage: "arrow.triangle.branch")
            } footer: {
                Text("**6760 purchases become expenses, cashback becomes refund income, **0023 withdrawals transfer to Cash, and bill payments transfer to the Loan Payment account.")
            }

            Section("Live Status") {
                statusRow(
                    title: "Daemon",
                    value: daemonStatus,
                    icon: snapshot.daemonRunning ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                statusRow(title: "Last Heartbeat", value: formatted(snapshot.lastHeartbeat), icon: "waveform.path.ecg")
                statusRow(title: "Last Scan", value: formatted(snapshot.lastScanDate), icon: "message.badge")
                statusRow(title: "Last Import", value: formatted(snapshot.lastImportDate), icon: "tray.and.arrow.down.fill")
                LabeledContent("Imported", value: "\(snapshot.totalImported)")
                LabeledContent("Duplicates", value: "\(snapshot.totalDuplicates)")
                LabeledContent("Parse Failures", value: "\(snapshot.totalParseFailures)")
                LabeledContent("Pending Queue", value: "\(snapshot.pendingCount)")
                Text(snapshot.lastResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section {
                if snapshot.logs.isEmpty {
                    Text("No log entries yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.logs.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.level.uppercased())
                                    .font(.caption2.bold())
                                Spacer()
                                Text(entry.date.formatted(date: .abbreviated, time: .standard))
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
            } header: {
                HStack {
                    Label("Temporary Console", systemImage: "terminal.fill")
                    Spacer()
                    Button("Refresh") { refresh() }
                        .font(.caption)
                }
            } footer: {
                Text("This console is temporary for device testing. It records parser decisions and errors but does not display the complete SMS body.")
            }
        }
        .navigationTitle("SMS Import Console")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            configuration = SMSImportConsoleService.loadConfiguration()
            applySuggestedMappings()
            refresh()
        }
        .onReceive(timer) { _ in refresh() }
        .alert("SMS Import", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private var activeAccounts: [LedgerAccount] {
        store.activeAccounts.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @ViewBuilder
    private func accountPicker(
        title: String,
        selection: Binding<String?>,
        suggestedWords: [String]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("Not Set").tag(String?.none)
            ForEach(activeAccounts) { account in
                Text("\(account.name) · \(account.currencyCode)")
                    .tag(Optional(account.id.uuidString))
            }
        }
    }

    private func cardBinding(_ ending: String) -> Binding<String?> {
        optionalBinding(
            get: { configuration.cardAccountIDs[ending] },
            set: { value in
                if let value {
                    configuration.cardAccountIDs[ending] = value
                } else {
                    configuration.cardAccountIDs.removeValue(forKey: ending)
                }
            }
        )
    }

    private func optionalBinding(
        get: @escaping () -> String?,
        set: @escaping (String?) -> Void
    ) -> Binding<String?> {
        Binding(get: get, set: set)
    }

    private func applySuggestedMappings() {
        if configuration.cardAccountIDs["6760"] == nil,
           let account = suggestedAccount(words: ["credit", "6760"]) {
            configuration.cardAccountIDs["6760"] = account.id.uuidString
        }
        if configuration.cardAccountIDs["0023"] == nil,
           let account = suggestedAccount(words: ["debit", "0023"]) {
            configuration.cardAccountIDs["0023"] = account.id.uuidString
        }
        if configuration.cashAccountID == nil,
           let account = suggestedAccount(words: ["cash"]) {
            configuration.cashAccountID = account.id.uuidString
        }
        if configuration.loanPaymentAccountID == nil,
           let account = suggestedAccount(words: ["loan", "payment"]) {
            configuration.loanPaymentAccountID = account.id.uuidString
        }
    }

    private func suggestedAccount(words: [String]) -> LedgerAccount? {
        activeAccounts.first { account in
            let name = account.name.lowercased()
            return words.contains { name.contains($0) }
        }
    }

    private func saveConfiguration(requestScan: Bool) {
        if requestScan { configuration.scanRequestID += 1 }
        do {
            try SMSImportConsoleService.saveConfiguration(configuration)
            notice = requestScan
                ? "The daemon was asked to scan recent bank messages."
                : "SMS import settings were saved."
            refresh()
        } catch {
            notice = "Settings could not be saved: \(error.localizedDescription)"
        }
    }

    private func refresh() {
        snapshot = SMSImportConsoleService.loadSnapshot()
    }

    private var daemonStatus: String {
        guard snapshot.daemonRunning, let heartbeat = snapshot.lastHeartbeat else {
            return "Not detected"
        }
        return Date().timeIntervalSince(heartbeat) < 15 ? "Running" : "Heartbeat stale"
    }

    private func formatted(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "Never"
    }

    private func statusRow(title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
'''
write("DailyLedger/Views/SMSImportConsoleView.swift", view)

settings = "DailyLedger/Views/SettingsView.swift"
anchor = '''                Section {
                    NavigationLink {
                        VendorRulesView()
'''
insert = '''                Section {
                    NavigationLink {
                        SMSImportConsoleView()
                    } label: {
                        SettingsRow(
                            title: "SMS Import Console",
                            subtitle: "Account mapping, daemon status and temporary logs",
                            icon: "terminal.fill",
                            color: AppTheme.orange
                        )
                    }
                } header: {
                    Label("Automatic Bank SMS", systemImage: "message.badge.filled.fill")
                } footer: {
                    Text("Requires the separate Next Ledger RootHide SMS Daemon package. The console helps verify message access, classification, account mapping and ledger writes.")
                }

''' + anchor
replace_once(settings, anchor, insert)

print("Added SMS importer configuration and temporary console UI.")
