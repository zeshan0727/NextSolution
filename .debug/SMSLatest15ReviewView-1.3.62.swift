import SwiftUI

struct SMSLatestReviewMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let sourceKey: String
    let sender: String
    let rowID: Int64
    let date: Date
    let details: String
    let queuedAt: Date
}

private struct SMSLatestReviewAIResult: Codable, Equatable {
    var transactionType: String
    var amount: String?
    var currency: String?
    var accountAlias: String?
    var vendor: String?
    var category: String?
    var confidence: Double
    var reason: String?
    var model: String?
}

private enum SMSLatestReviewError: LocalizedError {
    case missingKey
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: return "OpenAI API key is not saved in Settings → AI."
        case .invalidResponse: return "OpenAI did not return a readable SMS classification."
        }
    }
}

enum SMSLatest15ReviewService {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static var reviewURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("DailyLedger", isDirectory: true)
            .appendingPathComponent("sms-latest15-review.json")
    }

    static func load() -> [SMSLatestReviewMessage] {
        guard let data = try? Data(contentsOf: reviewURL),
              let items = try? decoder.decode([SMSLatestReviewMessage].self, from: data) else { return [] }
        return items.sorted { $0.rowID > $1.rowID }
    }

    static func disposition(for id: UUID) -> String? {
        UserDefaults.standard.string(forKey: "SMSLatest15Disposition.\(id.uuidString)")
    }

    static func setDisposition(_ value: String?, for id: UUID) {
        let key = "SMSLatest15Disposition.\(id.uuidString)"
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

private enum SMSLatest15AIService {
    static func testConnection() async throws -> String {
        guard OpenAIService.shared.hasAPIKey else { throw SMSLatestReviewError.missingKey }
        let response = try await OpenAIService.shared.request(
            messages: [OpenAIMessage(role: "user", content: "Reply with exactly: Connected")],
            model: "gpt-4.1-nano",
            maxTokens: 20
        )
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "SMSLatest15OpenAIVerifiedAt")
        UserDefaults.standard.removeObject(forKey: "SMSLatest15OpenAILastError")
        return response
    }

    static func analyze(_ item: SMSLatestReviewMessage, historyContext: String) async throws -> SMSLatestReviewAIResult {
        guard OpenAIService.shared.hasAPIKey else { throw SMSLatestReviewError.missingKey }
        let system = """
        You help a user review one complete incoming phone message for a personal ledger. Return JSON only. Classify it as income, expense, transfer, not_transaction, or unknown. Never invent an amount, currency, account, merchant, or direction. OTPs, marketing, login/security notices, balance-only notices, declined/failed notices without a posted movement, and personal chat messages are not_transaction. If it may be financial but you cannot determine the movement, use unknown. Confidence is 0 to 1. Use previous-ledger examples only as hints. A card transaction reversal/refund should be income with category Refund. An ATM cash deposit credited to a bank account is normally a transfer from Cash to Bank, not ordinary income, unless the message/history clearly indicates otherwise.
        """
        let prompt = """
        JSON schema:
        {"transactionType":"income|expense|transfer|not_transaction|unknown","amount":"number or null","currency":"code or null","accountAlias":"account/card hint or null","vendor":"merchant/counterparty/purpose or null","category":"short category or null","confidence":0.0,"reason":"short explanation"}

        Sender: \(item.sender.isEmpty ? "Unknown" : item.sender)
        Complete message text:
        \(item.details)

        Previous ledger/category hints (may be empty; never override the actual SMS):
        \(historyContext)
        """

        var lastError: Error?
        for model in ["gpt-4.1-nano", "gpt-4o-mini"] {
            do {
                let raw = try await OpenAIService.shared.request(
                    messages: [
                        OpenAIMessage(role: "system", content: system),
                        OpenAIMessage(role: "user", content: prompt)
                    ],
                    model: model,
                    maxTokens: 320
                )
                guard let start = raw.firstIndex(of: "{"),
                      let end = raw.lastIndex(of: "}"), start <= end,
                      let data = String(raw[start...end]).data(using: .utf8),
                      var result = try? JSONDecoder().decode(SMSLatestReviewAIResult.self, from: data) else {
                    throw SMSLatestReviewError.invalidResponse
                }
                let allowed = ["income", "expense", "transfer", "not_transaction", "unknown"]
                result.transactionType = result.transactionType.lowercased()
                guard allowed.contains(result.transactionType) else { throw SMSLatestReviewError.invalidResponse }
                result.confidence = min(max(result.confidence, 0), 1)
                result.model = model
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "SMSLatest15OpenAIVerifiedAt")
                UserDefaults.standard.removeObject(forKey: "SMSLatest15OpenAILastError")
                return result
            } catch {
                lastError = error
            }
        }
        let error = lastError ?? SMSLatestReviewError.invalidResponse
        UserDefaults.standard.set(error.localizedDescription, forKey: "SMSLatest15OpenAILastError")
        throw error
    }
}

struct SMSLatest15ReviewView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var items: [SMSLatestReviewMessage] = []
    @State private var results: [UUID: SMSLatestReviewAIResult] = [:]
    @State private var aiRunning = false
    @State private var aiCurrent = 0
    @State private var aiTotal = 0
    @State private var aiLog: [String] = []
    @State private var connectionStatus = "Not tested"
    @State private var testingConnection = false
    @State private var notice: String?

    var body: some View {
        List {
            Section("Review Pipeline") {
                LabeledContent("Messages Collected", value: "\(items.count) / 15")
                LabeledContent("Pending Review", value: "\(pendingItems.count)")
                LabeledContent("OpenAI Key", value: OpenAIService.shared.hasAPIKey ? "Saved" : "Missing")
                LabeledContent("OpenAI Test", value: connectionStatus)

                HStack {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        Label(testingConnection ? "Testing…" : "Test OpenAI", systemImage: "checkmark.shield.fill")
                    }
                    .disabled(testingConnection || !OpenAIService.shared.hasAPIKey)

                    Button {
                        Task { await analyzePending() }
                    } label: {
                        Label(aiRunning ? "Analyzing…" : "Analyze Pending", systemImage: "sparkles")
                    }
                    .disabled(aiRunning || pendingItems.isEmpty || !OpenAIService.shared.hasAPIKey)
                }

                if aiRunning || aiTotal > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: aiProgress)
                        HStack {
                            Text(aiRunning ? "AI analyzing message \(min(aiCurrent + 1, max(aiTotal, 1))) of \(aiTotal)" : "AI batch finished")
                            Spacer()
                            Text("\(Int((aiProgress * 100).rounded()))%")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if !aiLog.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Progress Log")
                            .font(.caption.bold())
                        ForEach(Array(aiLog.suffix(8).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if items.isEmpty {
                Section {
                    Text("No latest-15 review data is available. Return to SMS Import Console and tap Collect Latest 15 Messages.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(items) { item in
                    Section {
                        HStack {
                            Text(item.sender.isEmpty ? "Unknown sender" : item.sender)
                                .font(.headline)
                            Spacer()
                            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(item.details)
                            .font(.body)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        if let disposition = SMSLatest15ReviewService.disposition(for: item.id) {
                            LabeledContent("Review Status", value: disposition.capitalized)
                        }

                        if let result = results[item.id] {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("AI Suggestion")
                                    .font(.caption.bold())
                                LabeledContent("Nature", value: result.transactionType.replacingOccurrences(of: "_", with: " ").capitalized)
                                if let amount = result.amount, let currency = result.currency {
                                    LabeledContent("Amount", value: "\(currency.uppercased()) \(amount)")
                                }
                                if let vendor = result.vendor, !vendor.isEmpty {
                                    LabeledContent("Merchant / Purpose", value: vendor)
                                }
                                LabeledContent("Confidence", value: "\(Int((result.confidence * 100).rounded()))%")
                                if let reason = result.reason, !reason.isEmpty {
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        HStack {
                            Button {
                                Task { await analyzeOne(item) }
                            } label: {
                                Label("Ask AI", systemImage: "sparkles")
                            }
                            .disabled(aiRunning || !OpenAIService.shared.hasAPIKey)

                            if let result = results[item.id], canCreateDraft(result) {
                                Button {
                                    createDraft(item: item, result: result)
                                } label: {
                                    Label("Send to Drafts", systemImage: "tray.and.arrow.down.fill")
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            Button(role: .destructive) {
                                SMSLatest15ReviewService.setDisposition("rejected", for: item.id)
                                results.removeValue(forKey: item.id)
                                reload()
                            } label: {
                                Label("Reject", systemImage: "xmark.circle")
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Latest 15 Messages")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reload()
            if OpenAIService.shared.hasAPIKey,
               UserDefaults.standard.double(forKey: "SMSLatest15OpenAIVerifiedAt") > 0 {
                connectionStatus = "Verified previously"
            } else if !OpenAIService.shared.hasAPIKey {
                connectionStatus = "API key required"
            }
        }
        .alert("SMS Review", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private var pendingItems: [SMSLatestReviewMessage] {
        items.filter { SMSLatest15ReviewService.disposition(for: $0.id) == nil }
    }

    private var aiProgress: Double {
        guard aiTotal > 0 else { return 0 }
        return min(max(Double(aiCurrent) / Double(aiTotal), 0), 1)
    }

    private func reload() {
        items = SMSLatest15ReviewService.load()
    }

    @MainActor
    private func testConnection() async {
        testingConnection = true
        connectionStatus = "Testing…"
        defer { testingConnection = false }
        do {
            _ = try await SMSLatest15AIService.testConnection()
            connectionStatus = "Connected · API request passed"
            aiLog.append("OpenAI connection test passed using SMS model.")
        } catch {
            connectionStatus = "Error"
            aiLog.append("OpenAI test error: \(error.localizedDescription)")
            notice = "OpenAI test failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func analyzePending() async {
        let batch = pendingItems
        guard !batch.isEmpty else { return }
        aiRunning = true
        aiCurrent = 0
        aiTotal = batch.count
        aiLog = ["Starting AI review of \(batch.count) message(s)."]
        defer {
            aiRunning = false
            aiCurrent = aiTotal
        }

        for (index, item) in batch.enumerated() {
            aiCurrent = index
            aiLog.append("\(index + 1)/\(batch.count) · Reading row \(item.rowID)…")
            do {
                let result = try await SMSLatest15AIService.analyze(item, historyContext: historyContext(for: item))
                results[item.id] = result
                connectionStatus = "Connected · AI responding"
                aiLog.append("\(index + 1)/\(batch.count) · \(result.transactionType) · \(Int((result.confidence * 100).rounded()))%")
            } catch {
                connectionStatus = "Error"
                aiLog.append("\(index + 1)/\(batch.count) · ERROR: \(error.localizedDescription)")
                // Stop the batch on a connection/API error; do not loop endlessly.
                notice = "AI stopped at message \(index + 1): \(error.localizedDescription)"
                return
            }
            aiCurrent = index + 1
        }
        aiLog.append("AI review finished. Review each suggestion, then Send to Drafts or Reject.")
    }

    @MainActor
    private func analyzeOne(_ item: SMSLatestReviewMessage) async {
        aiRunning = true
        aiCurrent = 0
        aiTotal = 1
        aiLog.append("Analyzing row \(item.rowID)…")
        defer {
            aiRunning = false
            aiCurrent = 1
        }
        do {
            let result = try await SMSLatest15AIService.analyze(item, historyContext: historyContext(for: item))
            results[item.id] = result
            connectionStatus = "Connected · AI responding"
            aiLog.append("Row \(item.rowID): \(result.transactionType), \(Int((result.confidence * 100).rounded()))%")
        } catch {
            connectionStatus = "Error"
            aiLog.append("Row \(item.rowID) ERROR: \(error.localizedDescription)")
            notice = "AI error: \(error.localizedDescription)"
        }
    }

    private func historyContext(for item: SMSLatestReviewMessage) -> String {
        let normalizedMessage = item.details.lowercased()
        let messageTokens = Set(
            normalizedMessage
                .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 4 }
        )

        var examples: [(score: Int, text: String)] = []
        for transaction in store.transactions.prefix(150) {
            let vendor = (transaction.vendor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let accountName = store.account(withID: transaction.accountID)?.name ?? ""
            let candidateText = "\(vendor) \(transaction.details) \(accountName)".lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            let candidateTokens = Set(candidateText.split(separator: " ").map(String.init).filter { $0.count >= 4 })
            let overlap = messageTokens.intersection(candidateTokens).count
            var score = overlap
            if !vendor.isEmpty && normalizedMessage.localizedCaseInsensitiveContains(vendor) { score += 6 }
            let digits = accountName.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            if digits.count >= 4, normalizedMessage.contains(String(digits.suffix(4))) { score += 4 }
            guard score > 0 else { continue }

            let nature: String
            if transaction.refundOfTransactionID != nil { nature = "Refund" }
            else { nature = transaction.type.title }
            examples.append((score, "\(nature) | category=\(transaction.category) | vendor=\(vendor.isEmpty ? "Unknown" : vendor) | account=\(accountName.isEmpty ? "Unknown" : accountName)"))
        }

        examples.sort { left, right in
            left.score == right.score ? left.text < right.text : left.score > right.score
        }
        var lines = Array(examples.prefix(8).map(\.text))

        for rule in store.settings.vendorRules.prefix(80) {
            if normalizedMessage.localizedCaseInsensitiveContains(rule.keyword) {
                lines.append("Learned vendor rule | \(rule.keyword) => \(rule.category)")
            }
            if lines.count >= 10 { break }
        }

        if normalizedMessage.contains("reversal of transaction") {
            lines.insert("Local format hint | card reversal => Refund (money returned)", at: 0)
        }
        if normalizedMessage.contains("atm cash deposit") && normalizedMessage.contains("credited") {
            lines.insert("Local format hint | ATM cash deposit credited => usually Cash to Bank transfer", at: 0)
        }
        if normalizedMessage.contains("used for") && normalizedMessage.contains("card ending") {
            lines.insert("Local format hint | card used for merchant amount => Expense", at: 0)
        }

        return lines.isEmpty ? "No similar previous data found." : lines.prefix(10).joined(separator: "\n")
    }

    private func canCreateDraft(_ result: SMSLatestReviewAIResult) -> Bool {
        guard ["income", "expense", "transfer"].contains(result.transactionType),
              let amount = result.amount?.replacingOccurrences(of: ",", with: ""),
              Decimal(string: amount) != nil,
              let currency = result.currency, !currency.isEmpty else { return false }
        return true
    }

    private func createDraft(item: SMSLatestReviewMessage, result: SMSLatestReviewAIResult) {
        guard canCreateDraft(result) else {
            notice = "AI did not provide enough information to create a transaction draft."
            return
        }
        let candidate = SMSAICandidate(
            id: item.id,
            sourceKey: item.sourceKey,
            sender: item.sender,
            rowID: item.rowID,
            date: item.date,
            details: item.details,
            queuedAt: item.queuedAt
        )
        let legacy = SMSAIRecognitionResult(
            transactionType: result.transactionType,
            amount: result.amount,
            currency: result.currency,
            accountAlias: result.accountAlias,
            vendor: result.vendor,
            category: result.category,
            confidence: result.confidence,
            reason: result.reason,
            provider: result.model.map { "OpenAI · \($0)" } ?? "OpenAI"
        )
        do {
            try SMSImportConsoleService.applyAIRecovery(legacy, to: candidate)
            SMSLatest15ReviewService.setDisposition("draft", for: item.id)
            aiLog.append("Row \(item.rowID) sent to editable Drafts.")
            notice = "Created an editable SMS draft. Open SMS Drafts to review account/category and approve it."
            reload()
        } catch {
            aiLog.append("Row \(item.rowID) draft error: \(error.localizedDescription)")
            notice = "Could not create draft: \(error.localizedDescription)"
        }
    }
}
