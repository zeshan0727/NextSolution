import SwiftUI

struct SMSImportConsoleView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var configuration = SMSImportConfiguration()
    @State private var snapshot = SMSImportConsoleSnapshot()
    @State private var installerDiagnostic = ""
    @State private var approvedSendersText = "Cb SMS"
    @State private var draftCount = 0
    @AppStorage("SMSAIRecognitionEnabledV1") private var aiRecognitionEnabled = false
    @State private var localManualScan = false
    @State private var manualScanRequestedAt: Date?
    @State private var aiProcessing = false
    @State private var aiProcessedCount = 0
    @State private var notice: String?
    @State private var loadingConfiguration = true

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                Toggle("SMS Detection", isOn: $configuration.enabled)
                Toggle("Auto Record", isOn: $configuration.autoRecord)
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
                    title: "Current Account xxx364001",
                    selection: cardBinding("364001"),
                    suggestedWords: ["364001", "current", "cbq"]
                )
                accountPicker(
                    title: "Cash Account",
                    selection: optionalBinding(
                        get: { configuration.cashAccountID },
                        set: { configuration.cashAccountID = $0 }
                    ),
                    suggestedWords: ["cash"]
                )
                TextField("Custom card/account ending", text: customEndingBinding)
                    .keyboardType(.numberPad)
                accountPicker(
                    title: "Custom Account",
                    selection: optionalBinding(
                        get: { configuration.customAccountID },
                        set: { configuration.customAccountID = $0 }
                    ),
                    suggestedWords: []
                )

                TextField("Approved senders, comma separated", text: $approvedSendersText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Stepper(value: $configuration.automaticScanIntervalHours, in: 1...168) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Recovery Scan Interval")
                        Text("Every \(configuration.automaticScanIntervalHours) hour\(configuration.automaticScanIntervalHours == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("New approved-bank SMS are captured into Review immediately before any parser or AI decision. Collect Latest 15 remains an unfiltered manual history check. Capture cannot be skipped just because classification fails.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    SMSDraftInboxView()
                } label: {
                    HStack {
                        Label("SMS Drafts", systemImage: "tray.full.fill")
                        Spacer()
                        Text("\(draftCount)")
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    saveConfiguration(requestScan: false)
                } label: {
                    Label("Save Import Settings", systemImage: "checkmark.circle.fill")
                }
                Button {
                    startManualScan()
                } label: {
                    Label(effectiveManualScanActive ? "Collecting Latest 15…" : "Collect Latest 15 Messages", systemImage: "arrow.clockwise.circle.fill")
                }
                .disabled(effectiveManualScanActive)

                if effectiveManualScanActive {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: scanProgress)
                        HStack {
                            Text(snapshot.scanPhase ?? "Waiting for daemon…")
                            Spacer()
                            Text("\(scanProgressPercent)%")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else if snapshot.scanInProgress == true {
                    Text("Previous scan status is stale. You can start a new Latest 15 scan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    SMSLatest15ReviewView()
                } label: {
                    Label("Review Latest 15 Messages (\(SMSLatest15ReviewService.load().count))", systemImage: "text.bubble.fill")
                }

                LabeledContent(
                    "AI Helper",
                    value: OpenAIService.shared.hasAPIKey ? "Ready · Test inside Latest 15 Review" : "OpenAI API required"
                )
                Text("Manual collection always shows the latest 15 incoming messages with their recovered full text. OpenAI is optional assistance inside Latest 15 Review; it never approves or records a message by itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    restoreRejectedForReview()
                } label: {
                    Label("Restore Rejected SMS for Review", systemImage: "arrow.uturn.backward.circle.fill")
                }
            } header: {
                Label("Account Mapping", systemImage: "arrow.triangle.branch")
            } footer: {
                Text("Only new or never-reviewed SMS from approved senders and mapped card endings become drafts. Nothing is written to the ledger until you approve it. Rejected and approved SMS cannot return.")
            }

            Section {
                NavigationLink {
                    SMSInstallerDiagnosticView()
                } label: {
                    Label("Installer Diagnostics", systemImage: "wrench.and.screwdriver.fill")
                }
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
                NavigationLink {
                    SMSImportLogsView()
                } label: {
                    HStack {
                        Label("Logs", systemImage: "doc.text.magnifyingglass")
                        Spacer()
                        Text("\(snapshot.logs.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("SMS Import Console")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
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
        if configuration.cardAccountIDs["364001"] == nil,
           let account = suggestedAccount(words: ["364001", "current", "cbq"]) {
            configuration.cardAccountIDs["364001"] = account.id.uuidString
        }
        if configuration.cashAccountID == nil,
           let account = suggestedAccount(words: ["cash"]) {
            configuration.cashAccountID = account.id.uuidString
        }
    }

    private func suggestedAccount(words: [String]) -> LedgerAccount? {
        activeAccounts.first { account in
            let name = account.name.lowercased()
            return words.contains { name.contains($0) }
        }
    }

    private var customEndingBinding: Binding<String> {
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

    private func saveConfiguration(requestScan: Bool) {
        configuration.approvedSenders = approvedSendersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if configuration.approvedSenders.isEmpty { configuration.approvedSenders = ["Cb SMS"] }
        configuration.automaticScanIntervalHours = min(max(configuration.automaticScanIntervalHours, 1), 168)
        if requestScan { configuration.scanRequestID += 1 }
        do {
            try SMSImportConsoleService.saveConfiguration(configuration)
            notice = requestScan ? nil : "SMS import settings were saved."
            refresh()
        } catch {
            notice = "Settings could not be saved: \(error.localizedDescription)"
        }
    }

    private func restoreRejectedForReview() {
        do {
            let recordedIDs = Set(store.transactions.map(\.id))
            let restored = try SMSImportConsoleService.restoreRejectedForReview(
                recordedTransactionIDs: recordedIDs
            )
            guard restored > 0 else {
                notice = "No rejected SMS IDs were found. Approved transactions and current drafts were left unchanged."
                return
            }
            configuration.scanRequestID += 1
            try SMSImportConsoleService.saveConfiguration(configuration)
            notice = "Restored \(restored) rejected SMS item\(restored == 1 ? "" : "s") for review. Collect Latest 15 again if you also want a fresh database review list."
            refresh()
        } catch {
            notice = "Rejected SMS could not be restored: \(error.localizedDescription)"
        }
    }

    private func startManualScan() {
        localManualScan = true
        manualScanRequestedAt = Date()
        saveConfiguration(requestScan: true)
        refresh()
    }

    private var effectiveManualScanActive: Bool {
        if let requested = manualScanRequestedAt,
           Date().timeIntervalSince(requested) <= 45,
           localManualScan || snapshot.scanInProgress == true {
            return true
        }
        return false
    }

    private var scanProgress: Double {
        let total = max(snapshot.scanProgressTotal ?? 15, 1)
        let current = min(max(snapshot.scanProgressCurrent ?? 0, 0), total)
        return Double(current) / Double(total)
    }

    private var scanProgressPercent: Int {
        Int((scanProgress * 100).rounded())
    }

    private func refresh() {
        snapshot = SMSImportConsoleService.loadSnapshot()
        installerDiagnostic = SMSImportConsoleService.loadInstallerDiagnostic()
        draftCount = SMSImportConsoleService.loadDrafts().count

        if localManualScan,
           snapshot.scanInProgress != true,
           let requested = manualScanRequestedAt,
           let completed = snapshot.lastScanDate,
           completed >= requested.addingTimeInterval(-1) {
            localManualScan = false
        }
        if localManualScan,
           let requested = manualScanRequestedAt,
           Date().timeIntervalSince(requested) > 45 {
            localManualScan = false
        }
    }

    private func startAIRecognitionIfNeeded() {
        guard OpenAIService.shared.hasAPIKey, !aiProcessing, SMSAIRecognitionService.isAvailable else { return }
        let databaseCandidates = SMSImportConsoleService.loadAICandidates()
        let drafts = SMSImportConsoleService.loadDrafts().filter {
            $0.kind.hasPrefix("review") && SMSAIRecognitionService.cachedResult(for: $0.id) == nil
        }
        guard !databaseCandidates.isEmpty || !drafts.isEmpty else { return }
        aiProcessing = true
        Task {
            var completed = 0

            // Database recovery is highest priority. One source row is sent once;
            // successful ignore/transaction results are marked processed atomically.
            for candidate in databaseCandidates.prefix(10) {
                do {
                    let result = try await SMSAIRecognitionService.analyze(candidate: candidate)
                    try SMSImportConsoleService.applyAIRecovery(result, to: candidate)
                    completed += 1
                } catch {
                    SMSAIRecognitionService.recordFailure(error)
                    // Keep the candidate queued so a network/API failure can retry.
                    break
                }
            }

            // Refresh after recovery so newly created AI drafts are not immediately
            // sent through a redundant second request.
            let remainingDrafts = SMSImportConsoleService.loadDrafts().filter {
                $0.kind.hasPrefix("review") && SMSAIRecognitionService.cachedResult(for: $0.id) == nil
            }
            for draft in remainingDrafts.prefix(10) {
                do {
                    _ = try await SMSAIRecognitionService.analyze(draft: draft)
                    completed += 1
                } catch {
                    SMSAIRecognitionService.recordFailure(error)
                    break
                }
            }
            await MainActor.run {
                aiProcessedCount += completed
                aiProcessing = false
                refresh()
            }
        }
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

private struct SMSInstallerDiagnosticView: View {
    @State private var diagnostic = ""

    var body: some View {
        List {
            Section("Installer Diagnostic") {
                if diagnostic.isEmpty {
                    Text("No installer diagnostic is available yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(diagnostic)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            Section {
                Button("Refresh") { reload() }
            }
        }
        .navigationTitle("Installer Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private func reload() {
        diagnostic = SMSImportConsoleService.loadInstallerDiagnostic()
    }
}

private struct SMSAIRecognitionStatusView: View {
    @State private var testing = false
    @State private var message: String?
    @State private var refreshToken = UUID()

    private var provider: String {
        _ = refreshToken
        return UserDefaults.standard.string(forKey: "SMSAILastProviderV1") ?? "None yet"
    }

    private var confidence: String {
        _ = refreshToken
        let value = UserDefaults.standard.integer(forKey: "SMSAILastConfidenceV1")
        return UserDefaults.standard.object(forKey: "SMSAILastConfidenceV1") == nil ? "—" : "\(value)%"
    }

    private var lastType: String {
        _ = refreshToken
        return UserDefaults.standard.string(forKey: "SMSAILastTypeV1") ?? "—"
    }

    private var lastSuccess: String {
        _ = refreshToken
        let raw = UserDefaults.standard.double(forKey: "SMSAILastSuccessV1")
        guard raw > 0 else { return "Never" }
        return Date(timeIntervalSince1970: raw).formatted(date: .abbreviated, time: .standard)
    }

    private var lastError: String? {
        _ = refreshToken
        return UserDefaults.standard.string(forKey: "SMSAILastErrorV1")
    }

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("AI available", value: SMSAIRecognitionService.isAvailable ? "Yes" : "No API key")
                LabeledContent("Last provider", value: provider)
                LabeledContent("Last successful call", value: lastSuccess)
            }
            Section("Last AI Result") {
                LabeledContent("Type", value: lastType.capitalized)
                LabeledContent("Confidence", value: confidence)
                if let lastError, !lastError.isEmpty {
                    Text("Last error: \(lastError)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    Task { await runTest() }
                } label: {
                    Label(testing ? "Testing AI…" : "Test AI on Latest Review Draft", systemImage: "checkmark.shield.fill")
                }
                .disabled(testing || !SMSAIRecognitionService.isAvailable)
                if testing { ProgressView() }
            } footer: {
                Text("A successful test must display the actual provider, returned type and confidence. The original SMS stays a review draft; this test never records a transaction.")
            }
        }
        .navigationTitle("AI Recognition")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: SMSAIRecognitionService.statusChanged)) { _ in
            refreshToken = UUID()
        }
    }

    @MainActor
    private func runTest() async {
        let candidates = SMSImportConsoleService.loadAICandidates()
        let drafts = SMSImportConsoleService.loadDrafts().filter { $0.kind.hasPrefix("review") }
        guard let candidate = candidates.first ?? drafts.first.map({ draft in
            SMSAICandidate(id: draft.id, sourceKey: draft.sourceKey, sender: draft.sender, rowID: draft.rowID, date: draft.date, details: draft.details, queuedAt: draft.queuedAt)
        }) else {
            message = "No unresolved database SMS is available. Run Manual Scan first."
            return
        }
        testing = true
        defer { testing = false }
        do {
            SMSAIRecognitionService.clearCache(for: candidate.id)
            let result = try await SMSAIRecognitionService.analyze(candidate: candidate)
            message = "Verified database → \(result.provider ?? "AI"): \(result.transactionType.capitalized), \(Int((result.confidence * 100).rounded()))% confidence. Test does not record or remove the queue item."
            refreshToken = UUID()
        } catch {
            SMSAIRecognitionService.recordFailure(error)
            message = "AI test failed: \(error.localizedDescription)"
            refreshToken = UUID()
        }
    }
}

