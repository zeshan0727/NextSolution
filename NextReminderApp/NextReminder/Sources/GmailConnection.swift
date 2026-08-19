import AuthenticationServices
import Foundation
import SwiftUI
import UIKit

struct GmailConnectionRecord: Codable, Equatable {
    var connectorID: String
    var emailAddress: String
    var connectedAt: Date
}

final class GmailConnectionStore {
    static let shared = GmailConnectionStore()
    private let key = "NextReminder.GmailConnection.v1"
    private init() {}

    func load() -> GmailConnectionRecord? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GmailConnectionRecord.self, from: data)
    }

    func save(_ record: GmailConnectionRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
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
            return "Configure the HTTPS scheduler and API key in Automation Connections first."
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

    private let schedulerEndpointKey = "NextReminder.AutomationCloudEndpoint"
    private var activeSession: ASWebAuthenticationSession?

    private override init() {}

    func connect() async throws -> GmailConnectionRecord {
        var request = try makeRequest(path: "v1/connectors/gmail/start", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GmailStartPayload(callbackScheme: "nextreminder", appName: "Next Reminder")
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
            GmailConnectionStore.shared.save(record)
            return record
        }

        guard let sessionID = start.sessionID else {
            throw GmailConnectionError.callbackMissingConnection
        }
        let record = try await fetchStatus(sessionID: sessionID)
        GmailConnectionStore.shared.save(record)
        return record
    }

    func disconnect(connectorID: String) async throws {
        var request = try makeRequest(
            path: "v1/connectors/gmail/\(connectorID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? connectorID)",
            method: "DELETE"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        GmailConnectionStore.shared.clear()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
        return window ?? ASPresentationAnchor()
    }

    private func authenticate(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "nextreminder"
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
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
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

    private func fetchStatus(sessionID: String) async throws -> GmailConnectionRecord {
        let encoded = sessionID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sessionID
        let request = try makeRequest(path: "v1/connectors/gmail/status?session_id=\(encoded)", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let status = try JSONDecoder().decode(GmailStatusResponse.self, from: data)
        guard status.connected == true,
              let connectorID = status.connectorID,
              let email = status.emailAddress else {
            throw GmailConnectionError.server(status.message ?? "Gmail connection is not complete.")
        }
        return GmailConnectionRecord(connectorID: connectorID, emailAddress: email, connectedAt: Date())
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        let endpoint = UserDefaults.standard.string(forKey: schedulerEndpointKey) ?? ""
        let apiKey = AutomationKeychain.load()
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
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("NextReminder-iOS/1.2.1", forHTTPHeaderField: "User-Agent")
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

struct GmailConnectionCard: View {
    @Binding var draft: EmailAutomationSettings
    @EnvironmentObject private var emailStore: EmailAutomationStore
    @EnvironmentObject private var automationStore: AutomationStore

    @State private var record: GmailConnectionRecord?
    @State private var isConnecting = false
    @State private var isDisconnecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Gmail Sender Connection")

            if let record {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gmail connected")
                            .font(.headline)
                        Text(record.emailAddress)
                            .font(.subheadline)
                        Text("Secure OAuth connection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .nextCard()

                Button(role: .destructive) {
                    disconnect(record)
                } label: {
                    Label(isDisconnecting ? "Disconnecting…" : "Disconnect Gmail", systemImage: "link.badge.minus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .disabled(isDisconnecting)
            } else {
                Button {
                    connect()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isConnecting ? "Connecting Gmail…" : "Connect Gmail Account")
                                .font(.headline)
                            Text("Sign in with Google and approve email sending")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(.white)
                    .padding(15)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isConnecting || !automationStore.cloudConfiguration.isConfigured)

                if !automationStore.cloudConfiguration.isConfigured {
                    Label(
                        "Configure the HTTPS scheduler and API key in Automation Connections first.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Text("Your Gmail password is never entered here. Google OAuth tokens stay encrypted on the scheduler; the app stores only the connected email address and connector ID.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            record = GmailConnectionStore.shared.load()
            if let record {
                draft.remoteConnectorID = record.connectorID
                if draft.senderLabel.isEmpty { draft.senderLabel = record.emailAddress }
            }
        }
        .alert("Gmail Connection", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func connect() {
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                let connected = try await GmailOAuthClient.shared.connect()
                record = connected
                draft.remoteConnectorID = connected.connectorID
                draft.senderLabel = connected.emailAddress
                emailStore.save(draft)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func disconnect(_ record: GmailConnectionRecord) {
        isDisconnecting = true
        Task {
            defer { isDisconnecting = false }
            do {
                try await GmailOAuthClient.shared.disconnect(connectorID: record.connectorID)
                self.record = nil
                draft.remoteConnectorID = ""
                draft.senderLabel = ""
                emailStore.save(draft)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
