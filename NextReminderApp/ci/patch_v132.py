#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:240]!r}")
    path.write_text(text.replace(old, new, 1))


xpost = SOURCES / "XPostGenerator.swift"

replace_once(
    xpost,
    '''    case photoPermission
    case server(String)''',
    '''    case photoPermission
    case incomplete(String)
    case refused(String)
    case server(String)'''
)
replace_once(
    xpost,
    '''        case .photoPermission:
            return "Allow Next Reminder to add photos in iPhone Settings."
        case .server(let message):''',
    '''        case .photoPermission:
            return "Allow Next Reminder to add photos in iPhone Settings."
        case .incomplete(let reason):
            return "OpenAI stopped before completing the draft (\(reason)). Try again."
        case .refused(let reason):
            return "OpenAI could not create this draft: \(reason)"
        case .server(let message):'''
)

replace_once(
    xpost,
    '''struct XPostOpenAIClient {
    func generateDraft(
        topic: XPostTopic,
        model: XPostTextModel,
        apiKey: String
    ) async throws -> XPostDraft {''',
    '''struct XPostGenerationResult {
    var draft: XPostDraft
    var inputTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int
    var totalTokens: Int
}

struct XPostOpenAIClient {
    func generateDraft(
        topic: XPostTopic,
        model: XPostTextModel,
        apiKey: String
    ) async throws -> XPostGenerationResult {'''
)

replace_once(
    xpost,
    '''            "store": false,
            "tools": [["type": "web_search"]],
            "instructions": instructions,
            "input": input,
            "max_output_tokens": 1800,
            "text": ["format": ["type": "json_schema", "name": "x_post_package", "strict": true, "schema": schema]]''',
    '''            "store": false,
            "reasoning": ["effort": "low"],
            "tools": [["type": "web_search", "search_context_size": "low"]],
            "max_tool_calls": 3,
            "instructions": instructions,
            "input": input,
            "max_output_tokens": 3200,
            "text": ["format": ["type": "json_schema", "name": "x_post_package", "strict": true, "schema": schema]]'''
)

replace_once(
    xpost,
    '''        let data = try await performJSONRequest(url: url, body: body, apiKey: key, timeout: 120)
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
        return draft''',
    '''        let data = try await performJSONRequest(url: url, body: body, apiKey: key, timeout: 120)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw XPostGeneratorError.invalidResponse
        }

        if let status = root["status"] as? String, status == "incomplete" {
            let details = root["incomplete_details"] as? [String: Any]
            let reason = details?["reason"] as? String ?? "incomplete response"
            throw XPostGeneratorError.incomplete(reason)
        }
        if let refusal = responseRefusal(root), !refusal.isEmpty {
            throw XPostGeneratorError.refused(refusal)
        }
        guard let text = responseOutputText(root),
              let resultData = text.data(using: .utf8) else {
            let status = root["status"] as? String ?? "unknown status"
            throw XPostGeneratorError.incomplete(status)
        }

        let draft: XPostDraft
        do {
            draft = try JSONDecoder().decode(XPostDraft.self, from: resultData)
        } catch {
            throw XPostGeneratorError.server("OpenAI produced text, but the structured draft could not be read: \(error.localizedDescription)")
        }
        guard let sourceURL = URL(string: draft.sourceURL),
              let scheme = sourceURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw XPostGeneratorError.invalidSource
        }

        let usage = root["usage"] as? [String: Any]
        let outputDetails = usage?["output_tokens_details"] as? [String: Any]
        return XPostGenerationResult(
            draft: draft,
            inputTokens: usage?["input_tokens"] as? Int ?? 0,
            outputTokens: usage?["output_tokens"] as? Int ?? 0,
            reasoningTokens: outputDetails?["reasoning_tokens"] as? Int ?? 0,
            totalTokens: usage?["total_tokens"] as? Int ?? 0
        )'''
)

replace_once(
    xpost,
    '''    private func responseOutputText(_ root: [String: Any]) -> String? {
        guard let output = root["output"] as? [[String: Any]] else { return nil }
        for item in output where item["type"] as? String == "message" {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content where part["type"] as? String == "output_text" {
                if let text = part["text"] as? String, !text.isEmpty { return text }
            }
        }
        return nil
    }''',
    '''    private func responseOutputText(_ root: [String: Any]) -> String? {
        guard let output = root["output"] as? [[String: Any]] else { return nil }
        for item in output where item["type"] as? String == "message" {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content where part["type"] as? String == "output_text" {
                if let text = part["text"] as? String, !text.isEmpty { return text }
            }
        }
        return nil
    }

    private func responseRefusal(_ root: [String: Any]) -> String? {
        guard let output = root["output"] as? [[String: Any]] else { return nil }
        for item in output where item["type"] as? String == "message" {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content where part["type"] as? String == "refusal" {
                if let refusal = part["refusal"] as? String { return refusal }
            }
        }
        return nil
    }'''
)

replace_once(
    xpost,
    '''    @Published var statusMessage: String?

    private let client = XPostOpenAIClient()''',
    '''    @Published var statusMessage: String?
    @Published var usageSummary: String?

    private let client = XPostOpenAIClient()'''
)
replace_once(
    xpost,
    '''        statusMessage = nil
        phase = "Searching and verifying news from the latest 7 days…"''',
    '''        statusMessage = nil
        usageSummary = nil
        phase = "Searching and verifying news from the latest 7 days…"'''
)
replace_once(
    xpost,
    '''            let generated = try await client.generateDraft(topic: topic, model: textModel, apiKey: key)
            draft = generated
            phase = "Generating the visual…"
            do {
                imageData = try await client.generateImage(prompt: generated.imagePrompt, quality: imageQuality, apiKey: key)''',
    '''            let result = try await client.generateDraft(topic: topic, model: textModel, apiKey: key)
            let generated = result.draft
            draft = generated
            usageSummary = "News draft usage: \(result.totalTokens.formatted()) tokens (input \(result.inputTokens.formatted()), output \(result.outputTokens.formatted()), reasoning \(result.reasoningTokens.formatted()))."
            phase = "Generating the visual…"
            do {
                imageData = try await client.generateImage(prompt: generated.imagePrompt, quality: imageQuality, apiKey: key)'''
)
replace_once(
    xpost,
    '''    func saveImageToPhotos() async {''',
    '''    func retryVisual(quality: XPostImageQuality) async {
        guard let draft, !isGenerating else { return }
        let key = OpenAIKeychain.load()
        guard !key.isEmpty else {
            errorMessage = XPostGeneratorError.missingAPIKey.localizedDescription
            return
        }
        isGenerating = true
        phase = "Retrying the visual only…"
        errorMessage = nil
        defer { isGenerating = false; phase = "" }
        do {
            imageData = try await client.generateImage(prompt: draft.imagePrompt, quality: quality, apiKey: key)
        } catch {
            errorMessage = "The visual failed: \(error.localizedDescription)"
        }
    }

    func saveImageToPhotos() async {'''
)

replace_once(
    xpost,
    '''                } else if !store.isGenerating {
                    emptyCard
                }''',
    '''                } else {
                    placeholderResults
                }'''
)
replace_once(
    xpost,
    '''    private var emptyCard: some View {
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
    }''',
    '''    private var placeholderResults: some View {
        VStack(spacing: 12) {
            placeholderCard(number: "01", title: "Visual Photo", icon: "photo.fill", message: store.isGenerating ? "The visual will be created after the news draft is complete." : "Generated visual will appear here.")
            placeholderCard(number: "02", title: "Post Details & Tags", icon: "text.bubble.fill", message: store.isGenerating ? "Searching and writing the post…" : "Post description and hashtags will appear here.")
            placeholderCard(number: "03", title: "Alt for Photo", icon: "accessibility", message: "Accessible photo description will appear here.")
            placeholderCard(number: "04", title: "First Comment", icon: "bubble.left.and.bubble.right.fill", message: "The first comment will appear here.")
            placeholderCard(number: "05", title: "News Source", icon: "link.circle.fill", message: "Verified source, date, and article link will appear here.")
        }
    }

    private func placeholderCard(number: String, title: String, icon: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(number: number, title: title, icon: icon)
            HStack(spacing: 10) {
                if store.isGenerating { ProgressView() }
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(13)
            .background(Color.nextBackground, in: RoundedRectangle(cornerRadius: 13))
        }
        .padding(15)
        .nextCard()
    }'''
)

replace_once(
    xpost,
    '''                    sourceCard(draft)
                    finalActions(draft)''',
    '''                    sourceCard(draft)
                    if let usage = store.usageSummary {
                        Text(usage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .nextCard()
                    }
                    finalActions(draft)'''
)
replace_once(
    xpost,
    '''            } else {
                Text("Visual is still being prepared or needs regeneration.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.nextBackground, in: RoundedRectangle(cornerRadius: 13))
            }''',
    '''            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The post draft is ready, but no visual is available yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await store.retryVisual(quality: imageQuality) }
                    } label: {
                        Label("Retry Visual Only", systemImage: "photo.badge.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OrangeActionButtonStyle())
                    .disabled(store.isGenerating)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.nextBackground, in: RoundedRectangle(cornerRadius: 13))
            }'''
)

project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.1"', 'CFBundleShortVersionString: "1.3.2"')
project_text = project_text.replace('CFBundleVersion: "11"', 'CFBundleVersion: "12"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.1"', 'MARKETING_VERSION: "1.3.2"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "11"', 'CURRENT_PROJECT_VERSION: "12"')
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.1 • iOS 16.0+", "Version 1.3.2 • iOS 16.0+"))

for path in SOURCES.glob("*.swift"):
    path.write_text(path.read_text().replace("NextReminder-iOS/1.3.1", "NextReminder-iOS/1.3.2"))

print("Next Reminder v1.3.2 X generator reliability patch applied successfully.")
