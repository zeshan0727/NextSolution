import Foundation
import Photos
import Security
import SwiftUI
import UIKit

struct AIHubView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose an AI tool").font(.title2.bold())
                    Text("Use DeepSeek for reminder planning or OpenAI for complete X post drafts based on recent news.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    XPostGeneratorView()
                } label: {
                    toolCard(
                        icon: "bolt.horizontal.circle.fill",
                        title: "X Post Generator",
                        subtitle: "Latest 7-day news, one visual, post, tags, alt text, source and first comment",
                        ready: !OpenAIKeychain.load().isEmpty,
                        accent: .blue
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DeepSeekAIView()
                } label: {
                    toolCard(
                        icon: "sparkles",
                        title: "Reminder Assistant",
                        subtitle: "Plan your day, prioritize overdue work and improve reminder wording with DeepSeek",
                        ready: !DeepSeekKeychain.load().isEmpty,
                        accent: .purple
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    Label("90-Day X Goal", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                        .foregroundStyle(.nextOrange)
                    Text("Target: 5 million impressions and 500 verified followers. Drafts use strong curiosity hooks while staying tied to a real source.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(15)
                .nextCard()
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("AI")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toolCard(icon: String, title: String, subtitle: String, ready: Bool, accent: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(accent, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(title).font(.headline)
                    Text(ready ? "Ready" : "Setup")
                        .font(.caption2.bold())
                        .foregroundStyle(ready ? Color.green : Color.nextOrange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((ready ? Color.green : Color.nextOrange).opacity(0.12), in: Capsule())
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .nextCard()
    }
}

enum XPostTopic: String, CaseIterable, Identifiable, Codable {
    case highestPotential
    case artificialIntelligence
    case technology
    case businessFinance
    case world
    case entertainment
    case sports
    case qatarGulf

    var id: String { rawValue }
    var title: String {
        switch self {
        case .highestPotential: return "Highest Potential"
        case .artificialIntelligence: return "AI"
        case .technology: return "Technology"
        case .businessFinance: return "Business & Finance"
        case .world: return "World"
        case .entertainment: return "Entertainment"
        case .sports: return "Sports"
        case .qatarGulf: return "Qatar & Gulf"
        }
    }
    var searchInstruction: String {
        switch self {
        case .highestPotential: return "Search major categories and choose the single story with the strongest broad-audience impression potential."
        case .artificialIntelligence: return "Choose a major artificial intelligence story."
        case .technology: return "Choose a major consumer or business technology story."
        case .businessFinance: return "Choose a major business, markets, economy or personal-finance story."
        case .world: return "Choose a major world-news story with broad public interest."
        case .entertainment: return "Choose a major entertainment or culture story."
        case .sports: return "Choose a major sports story with broad public interest."
        case .qatarGulf: return "Choose a major Qatar or Gulf-region story with broad public interest."
        }
    }
}

enum XPostTextModel: String, CaseIterable, Identifiable, Codable {
    case fast = "gpt-5-mini"
    case quality = "gpt-5"
    var id: String { rawValue }
    var title: String { self == .fast ? "GPT-5 Mini" : "GPT-5" }
    var subtitle: String { self == .fast ? "Faster and lower cost" : "Best story selection and writing" }
}

enum XPostImageQuality: String, CaseIterable, Identifiable, Codable {
    case standard = "medium"
    case high = "high"
    var id: String { rawValue }
    var title: String { self == .standard ? "Standard" : "High" }
    var subtitle: String { self == .standard ? "Faster image generation" : "Sharper visual with higher API cost" }
}

struct XPostDraft: Codable, Equatable {
    var storyTitle: String
    var sourceTitle: String
    var sourceURL: String
    var sourceDate: String
    var postText: String
    var hashtags: [String]
    var altText: String
    var firstComment: String
    var imagePrompt: String
    var selectionReason: String

    var tagsText: String {
        hashtags.map { value in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.hasPrefix("#") ? cleaned : "#\(cleaned.replacingOccurrences(of: " ", with: ""))"
        }
        .filter { $0.count > 1 }
        .joined(separator: " ")
    }

    var composedPost: String {
        let post = postText.trimmingCharacters(in: .whitespacesAndNewlines)
        return tagsText.isEmpty ? post : "\(post)\n\n\(tagsText)"
    }
}

enum OpenAIKeychain {
    private static let service = "com.nextsolution.nextreminder.openai"
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
            throw XPostGeneratorError.secureStorage
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
              let data = result as? Data else { return "" }
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

enum XPostGeneratorError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case invalidSource
    case secureStorage
    case missingImage
    case photoPermission
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add your OpenAI API key in X Generator Settings first."
        case .invalidResponse: return "OpenAI returned an invalid result. Generate again."
        case .invalidSource: return "The generated result did not include a valid news source. Generate again."
        case .secureStorage: return "The OpenAI API key could not be saved securely."
        case .missingImage: return "There is no generated image to save."
        case .photoPermission: return "Allow Next Reminder to add photos in iPhone Settings."
        case .server(let message): return message
        }
    }
}

struct XPostOpenAIClient {
    func generateDraft(topic: XPostTopic, model: XPostTextModel, apiKey: String) async throws -> XPostDraft {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw XPostGeneratorError.missingAPIKey }
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw XPostGeneratorError.invalidResponse
        }

        let now = Date()
        let startDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: -7, to: now) ?? now
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let startText = formatter.string(from: startDate)
        let endText = formatter.string(from: now)

        let instructions = """
        You are the fixed X Post Generator inside Next Reminder. Research real news and create one complete manual-posting package for X.
        Rules:
        - Use web search and select exactly one real story published from \(startText) through \(endText), inclusive.
        - Prefer a reputable direct news article. Do not recycle an older story merely because it was discussed recently.
        - Select for broad impression potential: surprise, useful impact, urgency, novelty, debate and visual potential.
        - Write a curiosity-driven hook, but never invent, misquote, defame, exaggerate beyond the source or present speculation as fact.
        - The post plus hashtags should normally fit within 280 characters.
        - Use 3 to 5 relevant hashtags and avoid spam tags.
        - The first comment must add useful context or a thoughtful question. Do not beg for engagement.
        - Include the direct source title, date and URL.
        - The image prompt must describe an original 16:9 editorial visual with no logos, screenshots, fake quotation text or exact reproduction of a real person's face.
        - The visual must not falsely depict a fictional scene as documentary evidence.
        - Alt text must accurately describe that visual for a screen-reader user.
        - Return only the required structured result.
        """

        let input = """
        Generate one fresh X post package now.
        Topic preference: \(topic.title).
        \(topic.searchInstruction)
        The user's 90-day objective is 5 million impressions and 500 verified followers, but never promise results and never sacrifice factual accuracy.
        """

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "storyTitle": ["type": "string"],
                "sourceTitle": ["type": "string"],
                "sourceURL": ["type": "string"],
                "sourceDate": ["type": "string"],
                "postText": ["type": "string"],
                "hashtags": ["type": "array", "items": ["type": "string"], "minItems": 3, "maxItems": 5],
                "altText": ["type": "string"],
                "firstComment": ["type": "string"],
                "imagePrompt": ["type": "string"],
                "selectionReason": ["type": "string"]
            ],
            "required": ["storyTitle", "sourceTitle", "sourceURL", "sourceDate", "postText", "hashtags", "altText", "firstComment", "imagePrompt", "selectionReason"]
        ]

        let body: [String: Any] = [
            "model": model.rawValue,
            "store": false,
            "tools": [["type": "web_search"]],
            "instructions": instructions,
            "input": input,
            "max_output_tokens": 1800,
            "text": ["format": ["type": "json_schema", "name": "x_post_package", "strict": true, "schema": schema]]
        ]

        let data = try await performJSONRequest(url: url, body: body, apiKey: key, timeout: 120)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = responseOutputText(root),
              let resultData = text.data(using: .utf8) else {
            throw XPostGeneratorError.invalidResponse
        }
        let draft = try JSONDecoder().decode(XPostDraft.self, from: resultData)
        guard let sourceURL = URL(string: draft.sourceURL),
              let scheme = sourceURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw XPostGeneratorError.invalidSource
        }
        return draft
    }

    func generateImage(prompt: String, quality: XPostImageQuality, apiKey: String) async throws -> Data {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw XPostGeneratorError.missingAPIKey }
        guard let url = URL(string: "https://api.openai.com/v1/images/generations") else {
            throw XPostGeneratorError.invalidResponse
        }

        let finalPrompt = """
        Create one original 16:9 editorial image for an X news post.
        \(prompt)
        Make it visually strong at feed size, professionally lit and uncluttered. No logos, watermarks, publisher branding, copied screenshots, fake quotations or blocks of small text. Avoid an exact likeness of a real person and use symbolic or contextual storytelling when public figures are involved.
        """

        let body: [String: Any] = [
            "model": "gpt-image-1",
            "prompt": finalPrompt,
            "size": "1536x1024",
            "quality": quality.rawValue,
            "output_format": "png"
        ]
        let data = try await performJSONRequest(url: url, body: body, apiKey: key, timeout: 180)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]],
              let base64 = items.first?["b64_json"] as? String,
              let imageData = Data(base64Encoded: base64),
              !imageData.isEmpty else {
            throw XPostGeneratorError.invalidResponse
        }
        return imageData
    }

    func test(apiKey: String) async throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw XPostGeneratorError.missingAPIKey }
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            throw XPostGeneratorError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("NextReminder-iOS/1.3.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func performJSONRequest(url: URL, body: [String: Any], apiKey: String, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("NextReminder-iOS/1.3.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw XPostGeneratorError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message: String
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = root["error"] as? [String: Any],
               let detail = error["message"] as? String {
                message = detail
            } else {
                message = "OpenAI request failed (\(http.statusCode))."
            }
            throw XPostGeneratorError.server(message)
        }
    }

    private func responseOutputText(_ root: [String: Any]) -> String? {
        guard let output = root["output"] as? [[String: Any]] else { return nil }
        for item in output where item["type"] as? String == "message" {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content where part["type"] as? String == "output_text" {
                if let text = part["text"] as? String, !text.isEmpty { return text }
            }
        }
        return nil
    }
}

@MainActor
final class XPostGeneratorStore: ObservableObject {
    @Published var draft: XPostDraft?
    @Published var imageData: Data?
    @Published var isGenerating = false
    @Published var phase = ""
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let client = XPostOpenAIClient()

    func generate(topic: XPostTopic, textModel: XPostTextModel, imageQuality: XPostImageQuality) async {
        guard !isGenerating else { return }
        let key = OpenAIKeychain.load()
        guard !key.isEmpty else {
            errorMessage = XPostGeneratorError.missingAPIKey.localizedDescription
            return
        }
        isGenerating = true
        draft = nil
        imageData = nil
        errorMessage = nil
        statusMessage = nil
        phase = "Searching and verifying news from the latest 7 days…"
        defer { isGenerating = false; phase = "" }

        do {
            let generated = try await client.generateDraft(topic: topic, model: textModel, apiKey: key)
            draft = generated
            phase = "Generating the visual…"
            do {
                imageData = try await client.generateImage(prompt: generated.imagePrompt, quality: imageQuality, apiKey: key)
            } catch {
                errorMessage = "The post package was generated, but the visual failed: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveImageToPhotos() async {
        guard let imageData, let image = UIImage(data: imageData) else {
            errorMessage = XPostGeneratorError.missingImage.localizedDescription
            return
        }
        let authorization = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized || authorization == .limited else {
            errorMessage = XPostGeneratorError.photoPermission.localizedDescription
            return
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume(returning: ()) }
                    else { continuation.resume(throwing: XPostGeneratorError.invalidResponse) }
                }
            }
            statusMessage = "Visual saved to Photos."
        } catch {
            errorMessage = "The visual could not be saved: \(error.localizedDescription)"
        }
    }
}

struct XPostGeneratorView: View {
    @StateObject private var store = XPostGeneratorStore()
    @AppStorage("NextReminder.XPost.Topic") private var topicRaw = XPostTopic.highestPotential.rawValue
    @AppStorage("NextReminder.XPost.TextModel") private var textModelRaw = XPostTextModel.fast.rawValue
    @AppStorage("NextReminder.XPost.ImageQuality") private var imageQualityRaw = XPostImageQuality.standard.rawValue
    @State private var showSettings = false

    private var topic: XPostTopic { XPostTopic(rawValue: topicRaw) ?? .highestPotential }
    private var textModel: XPostTextModel { XPostTextModel(rawValue: textModelRaw) ?? .fast }
    private var imageQuality: XPostImageQuality { XPostImageQuality(rawValue: imageQualityRaw) ?? .standard }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if OpenAIKeychain.load().isEmpty { connectionCard }
                controls
                if store.isGenerating { progressCard }
                if let draft = store.draft {
                    visualCard
                    textCard(number: "02", title: "Post Details & Tags", icon: "text.bubble.fill", text: draft.composedPost, copyMessage: "Post copied.", footer: "\(draft.composedPost.count) characters")
                    textCard(number: "03", title: "Alt for Photo", icon: "accessibility", text: draft.altText, copyMessage: "Alt text copied.", footer: nil)
                    textCard(number: "04", title: "First Comment", icon: "bubble.left.and.bubble.right.fill", text: draft.firstComment, copyMessage: "First comment copied.", footer: nil)
                    sourceCard(draft)
                    finalActions(draft)
                } else if !store.isGenerating {
                    emptyCard
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("X Post Generator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { OpenAIXGeneratorSettingsView() }
        }
        .alert("X Post Generator", isPresented: Binding(
            get: { store.errorMessage != nil || store.statusMessage != nil },
            set: { if !$0 { store.errorMessage = nil; store.statusMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil; store.statusMessage = nil }
        } message: {
            Text(store.errorMessage ?? store.statusMessage ?? "")
        }
    }

    private var connectionCard: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 13) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect OpenAI").font(.headline)
                    Text("Add your API key securely before generating a post and visual.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .nextCard()
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Fixed News Command").font(.headline)
                    Text("Search window: latest 7 days").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            }
            Menu {
                ForEach(XPostTopic.allCases) { item in
                    Button { topicRaw = item.rawValue } label: {
                        Label(item.title, systemImage: item == topic ? "checkmark" : "circle")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "scope").foregroundStyle(.nextOrange)
                    Text("Topic: \(topic.title)").font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }
                .padding(13)
                .background(Color.nextBackground, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            Button {
                Task { await store.generate(topic: topic, textModel: textModel, imageQuality: imageQuality) }
            } label: {
                HStack(spacing: 9) {
                    if store.isGenerating { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
                    Text(store.isGenerating ? "Generating Package…" : "Generate X Post").font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(OrangeActionButtonStyle())
            .disabled(store.isGenerating || OpenAIKeychain.load().isEmpty)
            .opacity(OpenAIKeychain.load().isEmpty ? 0.55 : 1)
            Text("OpenAI searches current news, selects one source, writes the draft and creates one original visual. Review every result before posting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .nextCard()
    }

    private var progressCard: some View {
        HStack(spacing: 13) {
            ProgressView()
            VStack(alignment: .leading, spacing: 4) {
                Text("Creating your X package").font(.headline)
                Text(store.phase).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(15)
        .nextCard()
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "newspaper.fill").font(.system(size: 40)).foregroundStyle(.nextOrange)
            Text("One tap, one complete draft").font(.title3.bold())
            Text("Every result appears as Visual, Post + Tags, Alt Text, First Comment and Source.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 18)
        .nextCard()
    }

    private var visualCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(number: "01", title: "Visual Photo", icon: "photo.fill")
            if let data = store.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Button { Task { await store.saveImageToPhotos() } } label: {
                    Label("Save Visual to Photos", systemImage: "square.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OrangeActionButtonStyle())
            } else {
                Text("Visual is still being prepared or needs regeneration.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.nextBackground, in: RoundedRectangle(cornerRadius: 13))
            }
        }
        .padding(15)
        .nextCard()
    }

    private func textCard(number: String, title: String, icon: String, text: String, copyMessage: String, footer: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(number: number, title: title, icon: icon)
            Text(text)
                .font(.subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(Color.nextBackground, in: RoundedRectangle(cornerRadius: 13))
            HStack {
                if let footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                    store.statusMessage = copyMessage
                } label: {
                    Label("Copy", systemImage: "doc.on.doc.fill").font(.caption.bold())
                }
            }
        }
        .padding(15)
        .nextCard()
    }

    private func sourceCard(_ draft: XPostDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(number: "05", title: "News Source", icon: "link.circle.fill")
            Text(draft.storyTitle).font(.headline).textSelection(.enabled)
            Text(draft.sourceTitle).font(.subheadline.bold())
            Text("Published: \(draft.sourceDate)").font(.caption).foregroundStyle(.secondary)
            if let url = URL(string: draft.sourceURL) {
                Link(destination: url) {
                    Label("Open Source Article", systemImage: "safari.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(OrangeActionButtonStyle())
            }
            Button {
                UIPasteboard.general.string = draft.sourceURL
                store.statusMessage = "Source link copied."
            } label: {
                Label("Copy Source Link", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.nextBackground, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            Text(draft.selectionReason).font(.caption).foregroundStyle(.secondary)
        }
        .padding(15)
        .nextCard()
    }

    private func finalActions(_ draft: XPostDraft) -> some View {
        HStack(spacing: 11) {
            Button {
                Task { await store.generate(topic: topic, textModel: textModel, imageQuality: imageQuality) }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            Button {
                UIPasteboard.general.string = draft.composedPost
                var components = URLComponents(string: "https://x.com/intent/post")
                components?.queryItems = [URLQueryItem(name: "text", value: draft.composedPost)]
                if let url = components?.url { UIApplication.shared.open(url) }
            } label: {
                Label("Open X", systemImage: "arrow.up.right.square.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(OrangeActionButtonStyle())
        }
    }

    private func header(number: String, title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Text(number).font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Color.nextOrange, in: Circle())
            Image(systemName: icon).foregroundStyle(.nextOrange)
            Text(title).font(.headline)
            Spacer()
        }
    }
}

struct OpenAIXGeneratorSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("NextReminder.XPost.TextModel") private var textModelRaw = XPostTextModel.fast.rawValue
    @AppStorage("NextReminder.XPost.ImageQuality") private var imageQualityRaw = XPostImageQuality.standard.rawValue
    @State private var apiKey = OpenAIKeychain.load()
    @State private var isTesting = false
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "OpenAI Connection")
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("OpenAI API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(13)
                        .background(Color.nextBackground, in: RoundedRectangle(cornerRadius: 12))
                    Text("Stored in iPhone Keychain and excluded from app backups.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .nextCard()

                SectionHeader(title: "News & Writing Model")
                Picker("Text model", selection: $textModelRaw) {
                    ForEach(XPostTextModel.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)

                SectionHeader(title: "Visual Quality")
                Picker("Image quality", selection: $imageQualityRaw) {
                    ForEach(XPostImageQuality.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Web search checks the latest seven days", systemImage: "globe")
                    Label("GPT Image creates one original 16:9 visual", systemImage: "photo.badge.plus")
                    Label("No X password or X API access is required", systemImage: "lock.shield.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(14)
                .nextCard()

                Button {
                    do {
                        try OpenAIKeychain.save(apiKey)
                        apiKey = OpenAIKeychain.load()
                        notice = apiKey.isEmpty ? "OpenAI API key removed." : "OpenAI API key saved securely."
                    } catch { notice = error.localizedDescription }
                } label: {
                    Label("Save API Key", systemImage: "key.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(OrangeActionButtonStyle())

                Button {
                    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { notice = XPostGeneratorError.missingAPIKey.localizedDescription; return }
                    isTesting = true
                    Task {
                        defer { isTesting = false }
                        do {
                            try await XPostOpenAIClient().test(apiKey: key)
                            try OpenAIKeychain.save(key)
                            notice = "OpenAI connection successful."
                        } catch { notice = error.localizedDescription }
                    }
                } label: {
                    HStack {
                        if isTesting { ProgressView() }
                        Label(isTesting ? "Testing…" : "Test Connection", systemImage: "checkmark.shield.fill")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .disabled(isTesting)

                Button(role: .destructive) {
                    OpenAIKeychain.remove()
                    apiKey = ""
                    notice = "OpenAI API key removed."
                } label: {
                    Label("Remove API Key", systemImage: "trash.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("X Generator Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .alert("OpenAI Connection", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }
}
