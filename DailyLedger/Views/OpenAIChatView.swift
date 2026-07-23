import SwiftUI

private struct OpenAIChatItem: Identifiable, Codable {
    let id: UUID
    let role: String
    let content: String
    init(role: String, content: String) { id = UUID(); self.role = role; self.content = content }
}

struct OpenAIChatView: View {
    @AppStorage("OpenAIModel") private var model = "gpt-4.1-nano"
    @State private var messages = OpenAIChatHistory.load()
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            HStack {
                                if message.role == "user" { Spacer(minLength: 36) }
                                Text(message.content)
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
                TextField("Message OpenAI", text: $draft, axis: .vertical).lineLimit(1...5)
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }.padding().background(.ultraThinMaterial)
        }
        .navigationTitle("OpenAI Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: messages.count) { _ in OpenAIChatHistory.save(messages) }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(.init(role: "user", content: text)); draft = ""; sending = true; error = nil
        let requestMessages = [OpenAIMessage(role: "system", content: "Be concise and helpful.")] +
            messages.suffix(20).map { OpenAIMessage(role: $0.role, content: $0.content) }
        Task {
            do {
                let answer = try await OpenAIService.shared.request(messages: requestMessages, model: model)
                await MainActor.run { messages.append(.init(role: "assistant", content: answer)); sending = false }
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
