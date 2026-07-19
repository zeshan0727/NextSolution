import Foundation
import Security

struct DeepSeekMessage: Codable {
    let role: String
    let content: String
}

enum DeepSeekError: LocalizedError {
    case missingKey
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add and save a DeepSeek API key in Settings first."
        case .invalidResponse: return "DeepSeek returned an unreadable response."
        case .server(let message): return message
        }
    }
}

final class DeepSeekService: ObservableObject {
    static let shared = DeepSeekService()
    private static let keychainService = "com.nextsolution.dailyledger.deepseek"
    private static let keychainAccount = "api-key"

    private init() {}

    var hasAPIKey: Bool { !(loadAPIKey() ?? "").isEmpty }

    func saveAPIKey(_ value: String) throws {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            deleteAPIKey()
            return
        }
        let data = Data(cleaned.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DeepSeekError.server("The API key could not be saved securely.")
        }
    }

    func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    func request(
        messages: [DeepSeekMessage],
        model: String,
        maxTokens: Int = 650
    ) async throws -> String {
        guard let key = loadAPIKey(), !key.isEmpty else { throw DeepSeekError.missingKey }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            DeepSeekRequest(
                model: model,
                messages: messages,
                thinking: .init(type: "disabled"),
                maxTokens: min(max(maxTokens, 16), 650)
            )
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeepSeekError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(DeepSeekAPIError.self, from: data)
            throw DeepSeekError.server(apiError?.error.message ?? "DeepSeek request failed (HTTP \(http.statusCode)).")
        }
        guard let content = try? JSONDecoder().decode(DeepSeekResponse.self, from: data)
            .choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekError.invalidResponse
        }
        return content
    }
}

private struct DeepSeekRequest: Encodable {
    let model: String
    let messages: [DeepSeekMessage]
    let thinking: Thinking
    let maxTokens: Int

    private enum CodingKeys: String, CodingKey {
        case model, messages, thinking
        case maxTokens = "max_tokens"
    }

    struct Thinking: Encodable { let type: String }
}

private struct DeepSeekResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let message: DeepSeekMessage
    }
}

private struct DeepSeekAPIError: Decodable {
    let error: APIError
    struct APIError: Decodable { let message: String }
}
