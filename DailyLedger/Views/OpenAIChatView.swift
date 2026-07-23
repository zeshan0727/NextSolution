import SwiftUI

private enum OpenAIChatMode: String, CaseIterable, Identifiable {
    case ledger = "Ledger AI"
    case general = "General Chat"
    var id: String { rawValue }
}

private struct OpenAIChatItem: Identifiable, Codable {
    let id: UUID
    let role: String
    let content: String
    var transactionIDs: [UUID] = []
    init(role: String, content: String, transactionIDs: [UUID] = []) {
        id = UUID(); self.role = role; self.content = content; self.transactionIDs = transactionIDs
    }
}

struct OpenAIChatView: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage("OpenAIModel") private var model = "gpt-4.1-nano"
    @AppStorage("OpenAIChatMode") private var chatMode = OpenAIChatMode.ledger.rawValue
    @State private var messages = OpenAIChatHistory.load()
    @State private var generalSessionStart = OpenAIChatHistory.load().count
    @State private var pendingLedgerTransactionIDs: [UUID] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    @State private var selectedTransaction: LedgerTransaction?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Chat mode", selection: $chatMode) {
                ForEach(OpenAIChatMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            HStack {
                                if message.role == "user" { Spacer(minLength: 36) }
                                VStack(alignment: .leading, spacing: 9) {
                                    Text(message.content)
                                        .textSelection(.enabled)
                                    ForEach(message.transactionIDs, id: \.self) { id in
                                        if let transaction = store.transactions.first(where: { $0.id == id }) {
                                            Button {
                                                selectedTransaction = transaction
                                            } label: {
                                                Label("Open \(transaction.vendor ?? transaction.category)", systemImage: "arrow.up.right.square")
                                                    .font(.caption.bold())
                                                    .lineLimit(1)
                                            }.buttonStyle(.bordered)
                                        }
                                    }
                                }
                                    .padding(12)
                                    .background(message.role == "user" ? AppTheme.purple : Color.secondary.opacity(0.13),
                                                in: RoundedRectangle(cornerRadius: 16))
                                    .foregroundStyle(message.role == "user" ? .white : .primary)
                                if message.role != "user" { Spacer(minLength: 36) }
                            }.id(message.id)
                        }
                        if sending { ProgressView("OpenAI is responding…").padding() }
                    }.padding()
                }
                .onChange(of: messages.count) { _ in
                    if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(AppTheme.red).padding(.horizontal) }
            HStack(alignment: .bottom) {
                TextField(isLedgerMode ? "Discuss your transactions" : "Message OpenAI", text: $draft, axis: .vertical).lineLimit(1...5)
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }.padding().background(.ultraThinMaterial)
        }
        .navigationTitle("OpenAI Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: messages.count) { _ in OpenAIChatHistory.save(messages) }
        .onChange(of: chatMode) { mode in
            error = nil
            if mode == OpenAIChatMode.general.rawValue {
                pendingLedgerTransactionIDs = messages.last(where: {
                    !$0.transactionIDs.isEmpty
                })?.transactionIDs ?? []
                generalSessionStart = messages.count
            } else {
                pendingLedgerTransactionIDs = []
            }
        }
        .sheet(item: $selectedTransaction) {
            TransactionSnapshotView(transaction: $0).environmentObject(store)
        }
    }

    private var isLedgerMode: Bool { chatMode == OpenAIChatMode.ledger.rawValue }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let contextIDs = isLedgerMode ? [] : Array(pendingLedgerTransactionIDs.prefix(20))
        pendingLedgerTransactionIDs = []
        messages.append(.init(role: "user", content: text)); draft = ""; error = nil
        if isLedgerMode {
            let result = LedgerChatSearch.run(query: text, store: store, force: true)
            messages.append(.init(role: "assistant", content: result.response, transactionIDs: result.transactionIDs))
            return
        }
        guard OpenAIService.shared.hasAPIKey else {
            error = "Connect OpenAI in Settings first."
            return
        }
        sending = true
        let contextLines = contextIDs.compactMap { id -> String? in
            guard let item = store.transactions.first(where: { $0.id == id }) else { return nil }
            let account = store.account(withID: item.accountID)
            return "\(item.date.formatted(date: .abbreviated, time: .shortened)) | \(item.type.title) | \(account?.currencyCode ?? store.currencyCode) \(item.amount) | \(item.vendor ?? item.category) | \(account?.name ?? "Unknown")"
        }
        let context = contextLines.isEmpty ? "" :
            "\nTransactions handed off from Ledger AI for this request only:\n" + contextLines.joined(separator: "\n")
        let system = "Be concise and helpful. If transaction context is supplied, discuss only that data and do not invent missing records."
        let sessionMessages = messages.dropFirst(min(generalSessionStart, messages.count))
        var recent = sessionMessages.suffix(12).map { OpenAIMessage(role: $0.role, content: $0.content) }
        if !context.isEmpty, !recent.isEmpty {
            recent[recent.count - 1] = OpenAIMessage(role: "user", content: text + context)
        }
        let requestMessages = [OpenAIMessage(role: "system", content: system)] + recent
        Task {
            do {
                let answer = try await OpenAIService.shared.request(messages: requestMessages, model: model)
                await MainActor.run {
                    messages.append(.init(
                        role: "assistant",
                        content: answer
                    ))
                    sending = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; sending = false }
            }
        }
    }
}

private enum OpenAIChatHistory {
    static let key = "OpenAIPersistentChatHistory"
    static func load() -> [OpenAIChatItem] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([OpenAIChatItem].self, from: data)) ?? []
    }
    static func save(_ messages: [OpenAIChatItem]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(messages.suffix(100))), forKey: key)
    }
}
