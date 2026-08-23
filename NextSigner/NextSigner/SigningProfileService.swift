import Foundation
import Security
import Sodium

actor SigningProfileService {
    private struct RepositoryPublicKey: Decodable {
        let keyID: String
        let key: String

        enum CodingKeys: String, CodingKey {
            case keyID = "key_id"
            case key
        }
    }

    private let token: String
    private let configuration: GitHubConfiguration
    private let session: URLSession
    private let sodium = Sodium()
    private let apiVersion = "2026-03-10"

    init(token: String, configuration: GitHubConfiguration, session: URLSession = .shared) {
        self.token = token
        self.configuration = configuration
        self.session = session
    }

    func testSigningSecretAccess() async throws -> String {
        guard configuration.isValid else { throw NextSignerError.invalidConfiguration }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw NextSignerError.missingToken }

        _ = try await fetchRepositoryPublicKey()
        return "GitHub secret public-key access is working for \(configuration.owner)/\(configuration.repository)."
    }

    func saveSigningProfile(p12URL: URL, provisioningURL: URL, password: String) async throws {
        guard configuration.isValid else { throw NextSignerError.invalidConfiguration }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw NextSignerError.missingToken }
        guard !password.isEmpty else {
            throw NSError(domain: "NextSigner.Profile", code: 4101, userInfo: [NSLocalizedDescriptionKey: "Enter the P12 password."])
        }

        let p12Data = try readSecurityScoped(p12URL)
        let provisioningData = try readSecurityScoped(provisioningURL)
        guard !p12Data.isEmpty else {
            throw NSError(domain: "NextSigner.Profile", code: 4102, userInfo: [NSLocalizedDescriptionKey: "The selected P12 file is empty."])
        }
        guard !provisioningData.isEmpty else {
            throw NSError(domain: "NextSigner.Profile", code: 4103, userInfo: [NSLocalizedDescriptionKey: "The selected provisioning profile is empty."])
        }

        try validateP12(p12Data, password: password)
        let publicKey = try await fetchRepositoryPublicKey()

        try await putSecret(name: "NEXTSIGNER_P12_BASE64", value: p12Data.base64EncodedString(), publicKey: publicKey)
        try await putSecret(name: "NEXTSIGNER_MOBILEPROVISION_BASE64", value: provisioningData.base64EncodedString(), publicKey: publicKey)
        try await putSecret(name: "NEXTSIGNER_P12_PASSWORD", value: password, publicKey: publicKey)
    }

    private func readSecurityScoped(_ url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func validateP12(_ data: Data, password: String) throws {
        var items: CFArray?
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        let status = SecPKCS12Import(data as CFData, options, &items)
        guard status == errSecSuccess, let array = items as? [[String: Any]], !array.isEmpty else {
            let message: String
            if status == errSecAuthFailed {
                message = "The P12 password is incorrect."
            } else {
                message = "The selected P12 could not be opened (Security error \(status))."
            }
            throw NSError(domain: "NextSigner.Profile", code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func fetchRepositoryPublicKey() async throws -> RepositoryPublicKey {
        let endpoint = "/repos/\(configuration.owner)/\(configuration.repository)/actions/secrets/public-key"
        let url = try apiURL(endpoint)
        let (data, response) = try await session.data(for: request(url: url))
        try validate(response: response, data: data, operation: "GET Actions secrets public key", endpoint: endpoint)
        return try JSONDecoder().decode(RepositoryPublicKey.self, from: data)
    }

    private func putSecret(name: String, value: String, publicKey: RepositoryPublicKey) async throws {
        guard let keyData = Data(base64Encoded: publicKey.key),
              let sealed = sodium.box.seal(message: Array(value.utf8), recipientPublicKey: Array(keyData)) else {
            throw NSError(domain: "NextSigner.Profile", code: 4104, userInfo: [NSLocalizedDescriptionKey: "Could not encrypt the signing secret for GitHub."])
        }

        let payload: [String: String] = [
            "encrypted_value": Data(sealed).base64EncodedString(),
            "key_id": publicKey.keyID
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let endpoint = "/repos/\(configuration.owner)/\(configuration.repository)/actions/secrets/\(name)"
        let url = try apiURL(endpoint)
        let (data, response) = try await session.data(for: request(url: url, method: "PUT", body: body))
        try validate(response: response, data: data, accepted: [201, 204], operation: "PUT Actions secret \(name)", endpoint: endpoint)
    }

    private func request(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 120
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    private func apiURL(_ path: String) throws -> URL {
        guard let url = URL(string: "https://api.github.com\(path)") else { throw NextSignerError.malformedURL }
        return url
    }

    private func validate(
        response: URLResponse,
        data: Data,
        accepted: Set<Int>? = nil,
        operation: String,
        endpoint: String
    ) throws {
        guard let http = response as? HTTPURLResponse else { throw NextSignerError.invalidResponse }
        let allowed = accepted ?? Set(200...299)
        guard allowed.contains(http.statusCode) else {
            let apiMessage: String = {
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let value = object["message"] as? String,
                   !value.isEmpty {
                    return value
                }
                let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return raw.isEmpty ? "No response message" : String(raw.prefix(500))
            }()

            let acceptedPermissions = http.value(forHTTPHeaderField: "X-Accepted-GitHub-Permissions")
                ?? http.value(forHTTPHeaderField: "x-accepted-github-permissions")
                ?? "not returned"
            let oauthScopes = http.value(forHTTPHeaderField: "X-OAuth-Scopes")
                ?? http.value(forHTTPHeaderField: "x-oauth-scopes")
                ?? "not returned"
            let tokenSuffix = String(token.trimmingCharacters(in: .whitespacesAndNewlines).suffix(4))

            let detail = """
            GitHub HTTP \(http.statusCode)
            Operation: \(operation)
            Repository: \(configuration.owner)/\(configuration.repository)
            Endpoint: \(endpoint)
            GitHub message: \(apiMessage)
            Accepted permissions: \(acceptedPermissions)
            OAuth scopes: \(oauthScopes)
            Saved token ending: ••••\(tokenSuffix)
            """

            throw NSError(
                domain: "NextSigner.Profile",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: detail]
            )
        }
    }
}
