from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}: {old[:120]!r}; got {count}")
    write(path, text.replace(old, new, 1))


def replace_function_block(text: str, signature: str, replacement: str) -> str:
    start = text.find(signature)
    if start < 0:
        raise RuntimeError(f"Function signature not found: {signature}")
    brace = text.find("{", start)
    if brace < 0:
        raise RuntimeError(f"Opening brace not found: {signature}")
    depth = 0
    in_string = False
    escape = False
    i = brace
    while i < len(text):
        ch = text[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return text[:start] + replacement + text[i + 1:]
        i += 1
    raise RuntimeError(f"Closing brace not found: {signature}")


def remove_home_section_containing(text: str, needles) -> str:
    lines = text.splitlines(keepends=True)
    hit = None
    for i, line in enumerate(lines):
        if any(needle in line for needle in needles):
            hit = i
            break
    if hit is None:
        return text
    start = hit
    while start >= 0:
        stripped = lines[start].lstrip()
        indent = len(lines[start]) - len(stripped)
        if indent == 16 and (stripped.startswith("Section {") or stripped.startswith("Section(")):
            break
        start -= 1
    if start < 0:
        raise RuntimeError(f"Could not locate Settings section start for {needles}")
    end = hit + 1
    while end < len(lines):
        stripped = lines[end].lstrip()
        indent = len(lines[end]) - len(stripped)
        if indent == 16 and (stripped.startswith("Section {") or stripped.startswith("Section(")):
            break
        if indent == 0 and stripped.startswith("}"):
            break
        end += 1
    return "".join(lines[:start] + lines[end:])


replace_once("project.yml", 'MARKETING_VERSION: "1.3.73"', 'MARKETING_VERSION: "1.3.74"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "81"', 'CURRENT_PROJECT_VERSION: "82"')

ai_context = r'''import Foundation
import SwiftUI

@MainActor
final class AITransactionContextService: ObservableObject {
    static let shared = AITransactionContextService()
    static let fetchStep = 10

    @Published private(set) var loadedTransactionIDs: [UUID] = []
    @Published private(set) var initialized = false

    private init() {}

    func ensureDefault(from transactions: [LedgerTransaction]) {
        guard !initialized else { return }
        initialized = true
        fetchLatest10(from: transactions)
    }

    func fetchLatest10(from transactions: [LedgerTransaction]) {
        initialized = true
        loadedTransactionIDs = Array(sorted(transactions).prefix(Self.fetchStep).map(\.id))
    }

    func load10More(from transactions: [LedgerTransaction]) {
        initialized = true
        let ordered = sorted(transactions)
        let target = min(max(loadedTransactionIDs.count, 0) + Self.fetchStep, ordered.count)
        loadedTransactionIDs = Array(ordered.prefix(target).map(\.id))
    }

    func clear() {
        initialized = true
        loadedTransactionIDs = []
    }

    func transactions(from all: [LedgerTransaction]) -> [LedgerTransaction] {
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return loadedTransactionIDs.compactMap { byID[$0] }
    }

    private func sorted(_ transactions: [LedgerTransaction]) -> [LedgerTransaction] {
        transactions.sorted {
            if $0.date == $1.date { return $0.id.uuidString > $1.id.uuidString }
            return $0.date > $1.date
        }
    }
}

struct AITransactionContextControls: View {
    @EnvironmentObject private var store: LedgerStore
    @ObservedObject private var context = AITransactionContextService.shared

    private var loadedCount: Int { context.loadedTransactionIDs.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(AppTheme.purple)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Transaction Data")
                        .font(.subheadline.weight(.semibold))
                    Text(loadedCount == 0 ? "No transaction data fetched" : "\(loadedCount) transaction\(loadedCount == 1 ? "" : "s") loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Only the fetched snapshot can be sent to server AI. The default is the latest 10 transactions. More data requires your action.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if loadedCount == 0 {
                    Button {
                        context.fetchLatest10(from: store.transactions)
                    } label: {
                        Label("Fetch Latest 10", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else if loadedCount < store.transactions.count {
                    Button {
                        context.load10More(from: store.transactions)
                    } label: {
                        Label("Load 10 More", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }

                if loadedCount > 0 {
                    Button(role: .destructive) {
                        context.clear()
                    } label: {
                        Label("Clear Fetched Data", systemImage: "trash.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
'''
write("DailyLedger/Services/AITransactionContextService.swift", ai_context)

openai_view = r'''import SwiftUI

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
    @StateObject private var aiContext = AITransactionContextService.shared
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
            .padding(.horizontal)
            .padding(.top, 10)

            AITransactionContextControls()
                .padding(.horizontal)
                .padding(.vertical, 10)

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
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(message.role == "user" ? AppTheme.purple : Color.secondary.opacity(0.13),
                                            in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(message.role == "user" ? .white : .primary)
                                if message.role != "user" { Spacer(minLength: 36) }
                            }
                            .id(message.id)
                        }
                        if sending { ProgressView("OpenAI is responding…").padding() }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppTheme.red)
                    .padding(.horizontal)
            }

            HStack(alignment: .bottom) {
                TextField(isLedgerMode ? "Search your ledger locally" : "Message OpenAI", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("OpenAI Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            aiContext.ensureDefault(from: store.transactions)
        }
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

        if isLedgerMode {
            messages.append(.init(role: "user", content: text))
            draft = ""
            error = nil
            let result = LedgerChatSearch.run(query: text, store: store, force: true)
            messages.append(.init(role: "assistant", content: result.response, transactionIDs: result.transactionIDs))
            return
        }

        let fetchedIDs = aiContext.loadedTransactionIDs
        let allowed = Set(fetchedIDs)
        let hadLedgerHandoff = !pendingLedgerTransactionIDs.isEmpty
        let handoffIDs = pendingLedgerTransactionIDs.filter { allowed.contains($0) }
        let contextIDs = hadLedgerHandoff ? handoffIDs : fetchedIDs
        pendingLedgerTransactionIDs = []

        messages.append(.init(role: "user", content: text))
        draft = ""
        error = nil

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
            "\nUser-fetched Next Ledger transaction context (only this snapshot is authorized):\n" + contextLines.joined(separator: "\n")
        let system = "Be concise and helpful. You have no automatic ledger access. If transaction context is supplied, discuss only that user-fetched data and do not invent missing records. If no transaction context is supplied, do not claim to know ledger transactions."
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
                    messages.append(.init(role: "assistant", content: answer))
                    sending = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    sending = false
                }
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
'''
write("DailyLedger/Views/OpenAIChatView.swift", openai_view)

insights_path = "DailyLedger/Views/InsightsView.swift"
insights = read(insights_path)
if "@StateObject private var aiContext = AITransactionContextService.shared" not in insights:
    insights = insights.replace(
        "    @EnvironmentObject private var store: LedgerStore\n",
        "    @EnvironmentObject private var store: LedgerStore\n    @StateObject private var aiContext = AITransactionContextService.shared\n",
        1,
    )

recommendation_anchor = '                Section("DeepSeek Recommendations") {\n'
if recommendation_anchor not in insights:
    raise RuntimeError("DeepSeek Recommendations section anchor not found")
insights = insights.replace(
    recommendation_anchor,
    '''                Section("AI Data Access") {
                    AITransactionContextControls()
                }

''' + recommendation_anchor,
    1,
)

insights = insights.replace(
    "                        .disabled(loadingAdvice)\n",
    "                        .disabled(loadingAdvice || aiContext.loadedTransactionIDs.isEmpty)\n",
    1,
)

old_appear = '''            .onAppear {
                if fixedSuggestions.isEmpty { fixedSuggestions = makeSuggestions() }
            }
'''
new_appear = '''            .onAppear {
                aiContext.ensureDefault(from: store.transactions)
                if fixedSuggestions.isEmpty { fixedSuggestions = makeSuggestions() }
            }
'''
if old_appear not in insights:
    raise RuntimeError("Insights onAppear anchor not found")
insights = insights.replace(old_appear, new_appear, 1)

server_summary = r'''    private var serverSummary: String {
        let fetched = aiContext.transactions(from: store.transactions)
        let expenseSample = fetched.filter {
            $0.type == .expense && store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }
        let grouped = Dictionary(grouping: expenseSample, by: \.category)
        let ranked = grouped.map { category, transactions in
            (category: category, amount: expenseTotal(transactions), count: transactions.count)
        }
        .sorted { $0.amount > $1.amount }
        let categoryLines = ranked.prefix(10).map { item in
            "- \(item.category): \(NSDecimalNumber(decimal: item.amount).stringValue) \(store.currencyCode) across \(item.count) fetched transactions"
        }
        .joined(separator: "\n")
        let fetchedExpenseTotal = expenseSample.reduce(Decimal.zero) { $0 + $1.amount }
        return """
        Analyze only this user-fetched Next Ledger transaction snapshot. Do not infer or request the rest of the ledger.
        Currency: \(store.currencyCode)
        Fetched transactions: \(fetched.count)
        Fetched expenses in selected currency: \(NSDecimalNumber(decimal: fetchedExpenseTotal).stringValue)
        Fixed monthly income entered by user: \(NSDecimalNumber(decimal: monthlyBudgetIncome).stringValue)
        Categories inside fetched snapshot:
        \(categoryLines.isEmpty ? "- No fetched expenses in selected currency" : categoryLines)
        Return only 3 or 4 concise bullets and keep the complete response under 180 words.
        """
    }'''
insights = replace_function_block(insights, "    private var serverSummary: String {", server_summary)

old_footer = "Local suggestions stay on this iPhone. DeepSeek is contacted only when you press Generate or send a follow-up, using summarized categories and totals without raw SMS text, account numbers, or individual vendor descriptions."
new_footer = "Local suggestions stay on this iPhone. DeepSeek is contacted only when you press Generate or send a follow-up, and it receives only the transaction snapshot you explicitly fetched above. Default access is the latest 10; loading more is always manual."
insights = insights.replace(old_footer, new_footer, 1)
write(insights_path, insights)

settings_path = "DailyLedger/Views/SettingsView.swift"
settings = read(settings_path)
settings = remove_home_section_containing(settings, ["DeveloperLabView()", 'Label("Developer Lab"'])
settings = remove_home_section_containing(settings, ["ERPAccountingCenterView()", "ERP / Accounting Center", "ERP Accounting Center"])

count = settings.count('LabeledContent("Version", value: "1.3.73")')
if count != 1:
    raise RuntimeError(f"Expected visible Settings version 1.3.73 once, found {count}")
settings = settings.replace('LabeledContent("Version", value: "1.3.73")', 'LabeledContent("Version", value: "1.3.74")', 1)

root_open = '''        NavigationStack {
            List {
'''
root_new = '''        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 46, height: 46)
                                .background(AppTheme.purple, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Next Ledger Settings")
                                    .font(.title3.bold())
                                Text("Simple controls for your ledger, automation and privacy")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.bottom, 4)
'''
if root_open not in settings:
    raise RuntimeError("Settings root List anchor not found")
settings = settings.replace(root_open, root_new, 1)

root_close = '''}
            .navigationTitle("Settings")
'''
root_close_new = '''                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Settings")
'''
if root_close not in settings:
    raise RuntimeError("Settings root close anchor not found")
settings = settings.replace(root_close, root_close_new, 1)

row_meta = {
    "Display": ("Currency, appearance and visual theme", "paintpalette.fill", "AppTheme.purple"),
    "Accounting Period": ("Cycle start and period lock", "calendar.badge.clock", "AppTheme.blue"),
    "Import & Export": ("CSV, JSON backup and restore", "arrow.left.arrow.right", "AppTheme.green"),
    "Backup & Sync": ("iCloud and Google Drive", "icloud.fill", "AppTheme.blue"),
    "AI": ("API keys, models and AI access", "brain.head.profile", "AppTheme.purple"),
    "Shortcuts": ("Quick expense and income actions", "wand.and.stars", "AppTheme.orange"),
    "Automatic Bank SMS": ("Scheduled SMS import and review", "message.badge.filled.fill", "AppTheme.orange"),
    "Vendor Rules": ("Merchant categorization rules", "tag.fill", "AppTheme.purple"),
    "Planning & Categorization": ("Budgets and uncategorized review", "target", "AppTheme.green"),
    "About": ("Version and developer information", "info.circle.fill", "AppTheme.blue"),
}
for title, (subtitle, icon, tint) in row_meta.items():
    pattern = re.compile(r'Label\("' + re.escape(title) + r'", systemImage: "[^"]+"\)(?:\n\s+\.foregroundStyle\([^\n]+\))?')
    replacement = f'SettingsHomeLinkLabel(title: "{title}", subtitle: "{subtitle}", icon: "{icon}", tint: {tint})'
    settings, replaced = pattern.subn(replacement, settings, count=1)
    if replaced != 1:
        raise RuntimeError(f"Could not redesign Settings row: {title} (matches={replaced})")

settings = settings.replace(
    '''                }
                .padding(.horizontal, 16)
''',
    '''                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
''',
    1,
)

helper = r'''

private struct SettingsHomeLinkLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(13)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}
'''
settings += helper
write(settings_path, settings)

print("Prepared Next Ledger 1.3.74: server AI transaction snapshot defaults to latest 10 with manual +10 and clear controls; Developer Lab and ERP are hidden from Settings; Settings home redesigned as native cards.")
