import Foundation
import Security
import SwiftUI

enum DeepSeekModel: String, CaseIterable, Identifiable, Codable {
    case flash = "deepseek-v4-flash"
    case pro = "deepseek-v4-pro"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flash: return "DeepSeek V4 Flash"
        case .pro: return "DeepSeek V4 Pro"
        }
    }

    var subtitle: String {
        switch self {
        case .flash: return "Fast answers for everyday planning"
        case .pro: return "Stronger reasoning for complex planning"
        }
    }
}

struct DeepSeekChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    var id: UUID = UUID()
    var role: Role
    var content: String
    var createdAt: Date = Date()
}

enum DeepSeekKeychain {
    private static let service = "com.nextsolution.nextreminder.deepseek"
    private static let account = "api-key"

    static func save(_ value: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var item = query
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw DeepSeekError.secureStorage
        }
    }

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum DeepSeekError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case secureStorage
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your DeepSeek API key in AI Settings first."
        case .invalidResponse:
            return "DeepSeek returned an invalid response."
        case .secureStorage:
            return "The DeepSeek API key could not be saved securely."
        case .server(let message):
            return message
        }
    }
}

private struct DeepSeekAPIMessage: Codable {
    var role: String
    var content: String
}

private struct DeepSeekThinking: Codable {
    var type: String
}

private struct DeepSeekChatRequest: Encodable {
    var model: String
    var messages: [DeepSeekAPIMessage]
    var thinking: DeepSeekThinking
    var reasoningEffort: String
    var stream: Bool
    var maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case thinking
        case reasoningEffort = "reasoning_effort"
        case stream
        case maxTokens = "max_tokens"
    }
}

private struct DeepSeekChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }
        var message: Message
    }

    var choices: [Choice]
}

private struct DeepSeekErrorResponse: Decodable {
    struct APIError: Decodable {
        var message: String?
    }
    var error: APIError?
    var message: String?
}

struct DeepSeekClient {
    func complete(
        messages: [DeepSeekAPIMessage],
        model: DeepSeekModel,
        thinkingEnabled: Bool,
        apiKey: String
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DeepSeekError.missingAPIKey }
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            throw DeepSeekError.invalidResponse
        }

        let body = DeepSeekChatRequest(
            model: model.rawValue,
            messages: messages,
            thinking: DeepSeekThinking(type: thinkingEnabled ? "enabled" : "disabled"),
            reasoningEffort: "high",
            stream: false,
            maxTokens: 1800
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("NextReminder-iOS/1.3.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let decoded = try? JSONDecoder().decode(DeepSeekErrorResponse.self, from: data)
            let message = decoded?.error?.message
                ?? decoded?.message
                ?? "DeepSeek request failed (\(http.statusCode))."
            throw DeepSeekError.server(message)
        }

        guard let content = try JSONDecoder()
            .decode(DeepSeekChatResponse.self, from: data)
            .choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw DeepSeekError.invalidResponse
        }
        return content
    }
}

@MainActor
final class DeepSeekAIStore: ObservableObject {
    static let historyKey = "NextReminder.DeepSeek.ChatHistory.v1"

    @Published var messages: [DeepSeekChatMessage] = []
    @Published var isSending = false
    @Published var errorMessage: String?

    private let client = DeepSeekClient()

    init() {
        load()
    }

    func send(
        text: String,
        reminders: [ReminderItem],
        model: DeepSeekModel,
        thinkingEnabled: Bool,
        includeReminderContext: Bool
    ) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }

        messages.append(DeepSeekChatMessage(role: .user, content: prompt))
        persist()
        isSending = true
        defer { isSending = false }

        do {
            let apiMessages = buildMessages(
                reminders: reminders,
                includeReminderContext: includeReminderContext
            )
            let answer = try await client.complete(
                messages: apiMessages,
                model: model,
                thinkingEnabled: thinkingEnabled,
                apiKey: DeepSeekKeychain.load()
            )
            messages.append(DeepSeekChatMessage(role: .assistant, content: answer))
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        messages = []
        persist()
    }

    private func buildMessages(
        reminders: [ReminderItem],
        includeReminderContext: Bool
    ) -> [DeepSeekAPIMessage] {
        var system = """
        You are the AI assistant inside Next Reminder. Help the user plan tasks, prioritize reminders, improve reminder wording, identify overdue work, and prepare practical schedules. Be concise, action-oriented, and do not claim that you changed or completed a reminder. Use the user's local dates and times exactly as provided.
        """

        if includeReminderContext {
            let active = reminders
                .filter { !$0.isCompleted }
                .sorted { $0.effectiveDeadline < $1.effectiveDeadline }
                .prefix(60)
            if active.isEmpty {
                system += "\nThe user currently has no active reminders."
            } else {
                system += "\nCurrent active reminders:\n"
                system += active.map { reminder in
                    let note = reminder.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    let shortenedNote = note.count > 160 ? String(note.prefix(160)) + "…" : note
                    return "- \(reminder.title) | due \(reminder.dueDate.formatted(date: .abbreviated, time: .shortened)) | deadline \(reminder.deadlineDate?.formatted(date: .abbreviated, time: .shortened) ?? "none") | priority \(reminder.priority.title)\(shortenedNote.isEmpty ? "" : " | notes: \(shortenedNote)")"
                }.joined(separator: "\n")
            }
        }

        var apiMessages = [DeepSeekAPIMessage(role: "system", content: system)]
        apiMessages.append(contentsOf: messages.suffix(20).map {
            DeepSeekAPIMessage(role: $0.role.rawValue, content: $0.content)
        })
        return apiMessages
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let decoded = try? JSONDecoder().decode([DeepSeekChatMessage].self, from: data) else {
            messages = []
            return
        }
        messages = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(messages.suffix(100)) else { return }
        UserDefaults.standard.set(data, forKey: Self.historyKey)
    }
}

struct DeepSeekAIView: View {
    @EnvironmentObject private var reminderStore: ReminderStore
    @StateObject private var aiStore = DeepSeekAIStore()

    @AppStorage("NextReminder.DeepSeek.Model") private var modelRaw = DeepSeekModel.flash.rawValue
    @AppStorage("NextReminder.DeepSeek.Thinking") private var thinkingEnabled = false
    @AppStorage("NextReminder.DeepSeek.IncludeReminders") private var includeReminderContext = true

    @State private var inputText = ""
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool

    private var selectedModel: DeepSeekModel {
        DeepSeekModel(rawValue: modelRaw) ?? .flash
    }

    var body: some View {
        VStack(spacing: 0) {
            if DeepSeekKeychain.load().isEmpty {
                setupCard
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            if aiStore.messages.isEmpty {
                emptyState
            } else {
                conversation
            }

            composer
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("AI Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    ForEach(DeepSeekModel.allCases) { model in
                        Button {
                            modelRaw = model.rawValue
                        } label: {
                            Label(model.title, systemImage: selectedModel == model ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Label(selectedModel == .flash ? "Flash" : "Pro", systemImage: "cpu")
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    aiStore.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(aiStore.messages.isEmpty)
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                DeepSeekSettingsView()
            }
        }
        .alert("AI Assistant", isPresented: Binding(
            get: { aiStore.errorMessage != nil },
            set: { if !$0 { aiStore.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { aiStore.errorMessage = nil }
        } message: {
            Text(aiStore.errorMessage ?? "")
        }
    }

    private var setupCard: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "key.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.nextOrange, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect DeepSeek")
                        .font(.headline)
                    Text("Add your API key securely to start the reminder assistant.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .nextCard()
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 45)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.25), Color.nextOrange.opacity(0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sparkles")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .nextOrange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .frame(width: 108, height: 108)

                VStack(spacing: 7) {
                    Text("Plan with your reminders")
                        .font(.title2.bold())
                    Text(includeReminderContext
                         ? "AI can use your active reminder list to help organize priorities and schedules."
                         : "Reminder context is currently disabled in AI Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    quickPrompt("Plan my day", icon: "calendar.badge.clock")
                    quickPrompt("Prioritize overdue", icon: "exclamationmark.triangle.fill")
                    quickPrompt("Improve my reminder titles", icon: "text.badge.checkmark")
                    quickPrompt("Create a focus plan", icon: "scope")
                }
            }
            .padding(20)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(aiStore.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if aiStore.isSending {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("DeepSeek is preparing your plan…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(13)
                        .nextCard()
                        .id("thinking")
                    }
                }
                .padding(16)
            }
            .onChange(of: aiStore.messages.count) { _ in
                if let id = aiStore.messages.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .onChange(of: aiStore.isSending) { sending in
                if sending {
                    withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about your reminders…", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 18))

            Button {
                sendCurrentInput()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.nextOrange)
            }
            .disabled(
                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || aiStore.isSending
                    || DeepSeekKeychain.load().isEmpty
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func messageBubble(_ message: DeepSeekChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 45) }
            VStack(alignment: .leading, spacing: 5) {
                Text(message.role == .user ? "You" : "Next AI")
                    .font(.caption2.bold())
                    .foregroundStyle(message.role == .user ? Color.white.opacity(0.8) : Color.nextOrange)
                Text(message.content)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
            .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            .padding(13)
            .background(
                message.role == .user ? Color.nextOrange : Color.nextCard,
                in: RoundedRectangle(cornerRadius: 17)
            )
            if message.role == .assistant { Spacer(minLength: 30) }
        }
    }

    private func quickPrompt(_ title: String, icon: String) -> some View {
        Button {
            inputText = title
            sendCurrentInput()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.nextOrange)
                Text(title)
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .padding(13)
            .nextCard()
        }
        .buttonStyle(.plain)
        .disabled(DeepSeekKeychain.load().isEmpty)
    }

    private func sendCurrentInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        inputFocused = false
        Task {
            await aiStore.send(
                text: text,
                reminders: reminderStore.reminders,
                model: selectedModel,
                thinkingEnabled: thinkingEnabled,
                includeReminderContext: includeReminderContext
            )
        }
    }
}

struct DeepSeekSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("NextReminder.DeepSeek.Model") private var modelRaw = DeepSeekModel.flash.rawValue
    @AppStorage("NextReminder.DeepSeek.Thinking") private var thinkingEnabled = false
    @AppStorage("NextReminder.DeepSeek.IncludeReminders") private var includeReminderContext = true

    @State private var apiKey = DeepSeekKeychain.load()
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var selectedModel: Binding<DeepSeekModel> {
        Binding(
            get: { DeepSeekModel(rawValue: modelRaw) ?? .flash },
            set: { modelRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                connectionSection
                modelSection
                privacySection
                actionSection
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("DeepSeek AI Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .alert("DeepSeek AI", isPresented: Binding(
            get: { statusMessage != nil || errorMessage != nil },
            set: {
                if !$0 {
                    statusMessage = nil
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                statusMessage = nil
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? statusMessage ?? "")
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "DeepSeek Connection")
            VStack(alignment: .leading, spacing: 10) {
                SecureField("DeepSeek API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(13)
                    .background(Color.nextBackground, in: RoundedRectangle(cornerRadius: 12))
                Text("The API key is stored in the iPhone Keychain and is excluded from backups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .nextCard()
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "AI Model")
            ForEach(DeepSeekModel.allCases) { model in
                Button {
                    selectedModel.wrappedValue = model
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: model == .flash ? "bolt.fill" : "brain.head.profile")
                            .foregroundStyle(model == .flash ? Color.yellow : Color.purple)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.title)
                                .font(.headline)
                            Text(model.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selectedModel.wrappedValue == model ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedModel.wrappedValue == model ? Color.nextOrange : Color.secondary)
                    }
                    .padding(14)
                    .nextCard()
                }
                .buttonStyle(.plain)
            }

            Toggle("Enable thinking mode", isOn: $thinkingEnabled)
                .padding(14)
                .nextCard()
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Reminder Context")
            Toggle("Allow AI to read active reminders", isOn: $includeReminderContext)
                .padding(14)
                .nextCard()
            Text("When enabled, active reminder titles, dates, priorities, deadlines, and shortened notes are included with your AI request. Completed reminders are not sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                saveSettings()
            } label: {
                Label("Save AI Settings", systemImage: "checkmark.shield.fill")
            }
            .buttonStyle(OrangeActionButtonStyle())

            Button {
                testConnection()
            } label: {
                HStack {
                    if isTesting { ProgressView() }
                    Label(isTesting ? "Testing…" : "Test DeepSeek Connection", systemImage: "network")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isTesting)

            if !DeepSeekKeychain.load().isEmpty {
                Button(role: .destructive) {
                    DeepSeekKeychain.remove()
                    apiKey = ""
                    statusMessage = "DeepSeek API key removed."
                } label: {
                    Label("Remove API Key", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func saveSettings() {
        do {
            try DeepSeekKeychain.save(apiKey)
            apiKey = DeepSeekKeychain.load()
            statusMessage = "DeepSeek AI settings saved securely."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func testConnection() {
        isTesting = true
        Task {
            defer { isTesting = false }
            do {
                try DeepSeekKeychain.save(apiKey)
                let response = try await DeepSeekClient().complete(
                    messages: [
                        DeepSeekAPIMessage(role: "system", content: "Reply with a brief connection confirmation."),
                        DeepSeekAPIMessage(role: "user", content: "Confirm that Next Reminder can reach DeepSeek.")
                    ],
                    model: selectedModel.wrappedValue,
                    thinkingEnabled: false,
                    apiKey: DeepSeekKeychain.load()
                )
                statusMessage = response
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
