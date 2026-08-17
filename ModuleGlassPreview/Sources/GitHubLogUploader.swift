import Foundation
import Security

struct KeychainTokenStore {
    private static let service = "com.nextsolution.moduleglasspreview.github"
    private static let account = "github-pat"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else { return "" }
        return token
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return delete() }
        guard let data = trimmed.data(using: .utf8) else { return false }
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(key as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return true }
        if status != errSecItemNotFound { return false }
        var create = key
        create[kSecValueData as String] = data
        return SecItemAdd(create as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

enum GitHubUploadError: LocalizedError {
    case missingToken
    case invalidResponse
    case api(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingToken: return "GitHub token is not configured."
        case .invalidResponse: return "GitHub returned an invalid response."
        case .api(let status, let body): return "GitHub upload failed (HTTP \(status)): \(body)"
        }
    }
}

struct GitHubLogUploader {
    let owner = "zeshan0727"
    let repo = "NextSolution"
    let branch = "main"

    func upload(path: String, data: Data, token: String, commitMessage: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitHubUploadError.missingToken }

        let encodedPath = path.split(separator: "/").map { piece in
            String(piece).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(piece)
        }.joined(separator: "/")
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(encodedPath)") else {
            throw GitHubUploadError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 60
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("ModuleGlassPreview/1.1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "message": commitMessage,
            "content": data.base64EncodedString(),
            "branch": branch
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubUploadError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: responseData, encoding: .utf8) ?? "Unknown GitHub response"
            throw GitHubUploadError.api(http.statusCode, String(text.prefix(1200)))
        }
    }
}
