import AuthenticationServices
import Foundation
import SwiftUI
import UIKit

enum EmailDeliveryMode: String, CaseIterable, Codable, Identifiable {
    case gmailDirect
    case appleMail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gmailDirect: return "Gmail Direct"
        case .appleMail: return "Apple Mail Assisted"
        }
    }
}

struct EmailConfiguration: Codable, Equatable {
    var schedulerEndpoint: String
    var connectorID: String
    var connectedEmail: String
    var signature: String
    var preferredMode: EmailDeliveryMode

    static let defaults = EmailConfiguration(
        schedulerEndpoint: "",
        connectorID: "",
        connectedEmail: "",
        signature: "Thank you,\nZeeshan",
        preferredMode: .gmailDirect
    )
}

@MainActor
final class EmailConfigurationStore: ObservableObject {
    static let shared = EmailConfigurationStore()

    @Published private(set) var configuration: EmailConfiguration

    private let defaultsKey = "NextJob.EmailConfiguration.v1"
    private let apiKeyAccount = "scheduler-api-key"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(EmailConfiguration.self, from: data) {
            configuration = decoded
        } else {
            configuration = .defaults
        }
    }

    var schedulerAPIKey: String { SecureStore.load(account: apiKeyAccount) }
    var isSchedulerConfigured: Bool {
        let endpoint = configuration.schedulerEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return endpoint.lowercased().hasPrefix("https://") && !schedulerAPIKey.isEmpty
    }
    var isGmailConnected: Bool {
        isSchedulerConfigured && !configuration.connectorID.isEmpty && !configuration.connectedEmail.isEmpty
    }

    func update(_ transform: (inout EmailConfiguration) -> Void) {
        var copy = configuration
        transform(&copy)
        configuration = copy
        saveConfiguration()
    }

    func saveScheduler(endpoint: String, apiKey: String) throws {
        update { $0.schedulerEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines) }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            SecureStore.delete(account: apiKeyAccount)
        } else {
            try SecureStore.save(trimmed, account: apiKeyAccount)
        }
        objectWillChange.send()
    }

    func saveConnection(_ record: GmailConnectionRecord) {
        update {
            $0.connectorID = record.connectorID
            $0.connectedEmail = record.emailAddress
        }
    }

    func clearConnection() {
        update {
            $0.connectorID = ""
            $0.connectedEmail = ""
        }
    }

    private func saveConfiguration() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

struct GmailConnectionRecord: Codable, Equatable {
    var connectorID: String
    var emailAddress: String
    var connectedAt: Date
}

enum GmailConnectionError: LocalizedError {
    case schedulerNotConfigured
    case invalidEndpoint
    case invalidResponse
    case missingAuthorizationURL
    case cancelled
    case callbackMissingConnection
    case server(String)

    var errorDescription: String? {
        switch self {
        case .schedulerNotConfigured:
            return "Enter and save the same HTTPS scheduler URL and API key used by Next Reminder."
        case .invalidEndpoint:
            return "The scheduler URL must be a valid HTTPS address."
        case .invalidResponse:
            return "The Gmail connection service returned an invalid response."
        case .missingAuthorizationURL:
            return "The scheduler did not return a Google authorization link."
        case .cancelled:
            return "Gmail connection was cancelled."
        case .callbackMissingConnection:
            return "Google authorization completed, but the connector details were not returned."
        case .server(let message):
            return message
        }
    }
}

private struct GmailStartPayload: Encodable {
    var callbackScheme: String
    var appName: String
}

private struct GmailStartResponse: Decodable {
    var authorizationURL: String?
    var sessionID: String?
    var message: String?
}

private struct GmailStatusResponse: Decodable {
    var connected: Bool?
    var connectorID: String?
    var emailAddress: String?
    var message: String?
}

@MainActor
final class GmailOAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GmailOAuthClient()

    private var activeSession: ASWebAuthenticationSession?

    private override init() {}

    func connect(using store: EmailConfigurationStore) async throws -> GmailConnectionRecord {
        var request = try makeRequest(
            path: "v1/connectors/gmail/start",
            method: "POST",
            store: store
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GmailStartPayload(callbackScheme: "nextjob", appName: "Next Job")
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let start = try JSONDecoder().decode(GmailStartResponse.self, from: data)
        guard let rawURL = start.authorizationURL,
              let authorizationURL = URL(string: rawURL) else {
            throw GmailConnectionError.missingAuthorizationURL
        }

        let callbackURL = try await authenticate(at: authorizationURL)
        if let record = connection(from: callbackURL) {
            store.saveConnection(record)
            return record
        }

        guard let sessionID = start.sessionID else {
            throw GmailConnectionError.callbackMissingConnection
        }
        let record = try await fetchStatus(sessionID: sessionID, store: store)
        store.saveConnection(record)
        return record
    }

    func disconnect(using store: EmailConfigurationStore) async throws {
        let connectorID = store.configuration.connectorID
        guard !connectorID.isEmpty else {
            store.clearConnection()
            return
        }
        let encoded = connectorID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? connectorID
        let request = try makeRequest(
            path: "v1/connectors/gmail/\(encoded)",
            method: "DELETE",
            store: store
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        store.clearConnection()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
        return window ?? ASPresentationAnchor()
    }

    private func authenticate(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "nextjob"
            ) { callbackURL, error in
                self.activeSession = nil
                if let authenticationError = error as? ASWebAuthenticationSessionError,
                   authenticationError.code == .canceledLogin {
                    continuation.resume(throwing: GmailConnectionError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GmailConnectionError.callbackMissingConnection)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            guard session.start() else {
                activeSession = nil
                continuation.resume(throwing: GmailConnectionError.invalidResponse)
                return
            }
        }
    }

    private func connection(from url: URL) -> GmailConnectionRecord? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        })
        let connectorID = values["connector_id"] ?? values["connectorID"]
        let email = values["email"] ?? values["email_address"]
        guard let connectorID, !connectorID.isEmpty,
              let email, !email.isEmpty else { return nil }
        return GmailConnectionRecord(
            connectorID: connectorID,
            emailAddress: email,
            connectedAt: Date()
        )
    }

    private func fetchStatus(
        sessionID: String,
        store: EmailConfigurationStore
    ) async throws -> GmailConnectionRecord {
        let encoded = sessionID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sessionID
        let request = try makeRequest(
            path: "v1/connectors/gmail/status?session_id=\(encoded)",
            method: "GET",
            store: store
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let status = try JSONDecoder().decode(GmailStatusResponse.self, from: data)
        guard status.connected == true,
              let connectorID = status.connectorID,
              let email = status.emailAddress else {
            throw GmailConnectionError.server(status.message ?? "Gmail connection is not complete.")
        }
        return GmailConnectionRecord(
            connectorID: connectorID,
            emailAddress: email,
            connectedAt: Date()
        )
    }

    private func makeRequest(
        path: String,
        method: String,
        store: EmailConfigurationStore
    ) throws -> URLRequest {
        let endpoint = store.configuration.schedulerEndpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = store.schedulerAPIKey
        guard !endpoint.isEmpty, !apiKey.isEmpty else {
            throw GmailConnectionError.schedulerNotConfigured
        }
        let normalized = endpoint.hasSuffix("/") ? endpoint : endpoint + "/"
        guard let baseURL = URL(string: normalized),
              baseURL.scheme?.lowercased() == "https",
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw GmailConnectionError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("NextJob-iOS/1.0.2", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GmailConnectionError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(GmailStartResponse.self, from: data).message)
                ?? "Gmail connection request failed (\(http.statusCode))."
            throw GmailConnectionError.server(message)
        }
    }
}

struct DirectEmailAttachment {
    var fileName: String
    var mimeType: String
    var data: Data
}

private struct DirectEmailAttachmentPayload: Encodable {
    var fileName: String
    var mimeType: String
    var base64: String
}

private struct DirectEmailPayload: Encodable {
    var recipients: [String]
    var subject: String
    var body: String
    var remoteConnectorID: String
    var senderLabel: String
    var attachments: [DirectEmailAttachmentPayload]
}

private struct DirectEmailResponse: Decodable {
    var id: String?
    var message: String?
}

enum DirectEmailError: LocalizedError {
    case gmailNotReady
    case invalidRecipient
    case attachmentTooLarge
    case totalTooLarge
    case invalidEndpoint
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .gmailNotReady:
            return "Connect Gmail and save the scheduler settings before sending directly."
        case .invalidRecipient:
            return "Enter a valid recipient email address."
        case .attachmentTooLarge:
            return "Each direct Gmail attachment must be smaller than 10 MB. Use Apple Mail for larger files."
        case .totalTooLarge:
            return "Direct Gmail attachments must total less than 18 MB. Use Apple Mail for a larger job package."
        case .invalidEndpoint:
            return "The saved scheduler URL is invalid."
        case .invalidResponse:
            return "The email scheduler returned an invalid response."
        case .server(let message):
            return message
        }
    }
}

struct DirectEmailService {
    private let maximumSingleAttachment = 10_000_000
    private let maximumTotalAttachments = 18_000_000

    func send(
        recipient: String,
        subject: String,
        body: String,
        attachments: [DirectEmailAttachment],
        using store: EmailConfigurationStore
    ) async throws -> String {
        let configuration = store.configuration
        guard store.isGmailConnected else { throw DirectEmailError.gmailNotReady }
        guard Self.isValidEmail(recipient) else { throw DirectEmailError.invalidRecipient }
        guard attachments.allSatisfy({ $0.data.count <= maximumSingleAttachment }) else {
            throw DirectEmailError.attachmentTooLarge
        }
        guard attachments.reduce(0, { $0 + $1.data.count }) <= maximumTotalAttachments else {
            throw DirectEmailError.totalTooLarge
        }

        let normalized = configuration.schedulerEndpoint.hasSuffix("/")
            ? configuration.schedulerEndpoint
            : configuration.schedulerEndpoint + "/"
        guard let baseURL = URL(string: normalized),
              baseURL.scheme?.lowercased() == "https",
              let url = URL(string: "v1/file-shares", relativeTo: baseURL)?.absoluteURL else {
            throw DirectEmailError.invalidEndpoint
        }

        let payload = DirectEmailPayload(
            recipients: [recipient],
            subject: subject,
            body: body,
            remoteConnectorID: configuration.connectorID,
            senderLabel: configuration.connectedEmail,
            attachments: attachments.map {
                DirectEmailAttachmentPayload(
                    fileName: $0.fileName,
                    mimeType: $0.mimeType,
                    base64: $0.data.base64EncodedString()
                )
            }
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(store.schedulerAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("NextJob-iOS/1.0.2", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DirectEmailError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(DirectEmailResponse.self, from: data).message)
                ?? "Email sending failed (\(http.statusCode))."
            throw DirectEmailError.server(message)
        }
        return (try? JSONDecoder().decode(DirectEmailResponse.self, from: data).message)
            ?? "Email sent successfully."
    }

    static func isValidEmail(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = cleaned.firstIndex(of: "@"),
              cleaned[cleaned.index(after: at)...].contains(".") else {
            return false
        }
        return !cleaned.contains(" ") && cleaned.count <= 254
    }
}
