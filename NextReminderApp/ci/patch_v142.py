#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:360]!r}")
    path.write_text(text.replace(old, new, 1))


gmail = SOURCES / "GmailConnection.swift"

replace_once(
    gmail,
    '''import UserNotifications''',
    '''import UserNotifications
import Security'''
)

replace_once(
    gmail,
    '''struct GmailConnectionRecord: Codable, Equatable {
    var connectorID: String
    var emailAddress: String
    var connectedAt: Date
}''',
    '''struct GmailConnectionRecord: Codable, Equatable {
    var connectorID: String
    var emailAddress: String
    var connectedAt: Date
}

enum GmailRecoveryKeychain {
    private static let service = "com.nextsolution.nextreminder.gmail-recovery"

    static func save(_ recoveryBlob: String, connectorID: String) {
        remove(connectorID: connectorID)
        guard let data = recoveryBlob.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectorID,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(connectorID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectorID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(connectorID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectorID,
        ]
        SecItemDelete(query as CFDictionary)
    }
}'''
)

replace_once(
    gmail,
    '''private struct GmailConnectionHealthResponse: Decodable {
    var connected: Bool?
    var connectorID: String?
    var emailAddress: String?
    var message: String?
}''',
    '''private struct GmailConnectionHealthResponse: Decodable {
    var connected: Bool?
    var connectorID: String?
    var emailAddress: String?
    var message: String?
}

private struct GmailRecoveryResponse: Decodable {
    var connectorID: String?
    var emailAddress: String?
    var recoveryBlob: String?
    var message: String?
}

private struct GmailRestorePayload: Encodable {
    var connectorID: String
    var recoveryBlob: String
}

private struct GmailRestoreResponse: Decodable {
    var connected: Bool?
    var connectorID: String?
    var emailAddress: String?
    var message: String?
}'''
)

replace_once(
    gmail,
    '''        if let record = connection(from: callbackURL) {
            GmailConnectionStore.shared.save(record)
            return record
        }''',
    '''        if let record = connection(from: callbackURL) {
            GmailConnectionStore.shared.save(record)
            try? await cacheRecoveryBlob(connectorID: record.connectorID)
            return record
        }'''
)

replace_once(
    gmail,
    '''        let record = try await fetchStatus(sessionID: sessionID)
        GmailConnectionStore.shared.save(record)
        return record''',
    '''        let record = try await fetchStatus(sessionID: sessionID)
        GmailConnectionStore.shared.save(record)
        try? await cacheRecoveryBlob(connectorID: record.connectorID)
        return record'''
)

replace_once(
    gmail,
    '''        try validate(response: response, data: data)
        GmailConnectionStore.shared.clear()
    }

    func connectionHealth(connectorID: String) async throws -> GmailConnectionHealthResult {''',
    '''        try validate(response: response, data: data)
        GmailRecoveryKeychain.remove(connectorID: connectorID)
        GmailConnectionStore.shared.clear()
    }

    func cacheRecoveryBlob(connectorID: String) async throws {
        let encoded = connectorID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? connectorID
        let request = try makeRequest(
            path: "v1/connectors/gmail/\\(encoded)/recovery",
            method: "GET"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(GmailRecoveryResponse.self, from: data)
        guard let recoveryBlob = decoded.recoveryBlob, !recoveryBlob.isEmpty else {
            throw GmailConnectionError.invalidResponse
        }
        GmailRecoveryKeychain.save(recoveryBlob, connectorID: connectorID)
    }

    func restoreConnection(connectorID: String) async throws -> GmailConnectionRecord {
        guard let recoveryBlob = GmailRecoveryKeychain.load(connectorID: connectorID),
              !recoveryBlob.isEmpty else {
            throw GmailConnectionError.server("No secure Gmail recovery package is available. Connect Gmail once more.")
        }

        var request = try makeRequest(path: "v1/connectors/gmail/restore", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GmailRestorePayload(connectorID: connectorID, recoveryBlob: recoveryBlob)
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(GmailRestoreResponse.self, from: data)
        guard decoded.connected == true else {
            throw GmailConnectionError.server(decoded.message ?? "Gmail could not be restored.")
        }

        let current = GmailConnectionStore.shared.load()
        let record = GmailConnectionRecord(
            connectorID: decoded.connectorID ?? connectorID,
            emailAddress: decoded.emailAddress ?? current?.emailAddress ?? "",
            connectedAt: Date()
        )
        GmailConnectionStore.shared.save(record)
        GmailConnectionIssueStore.shared.clear()
        await GmailConnectionAlertManager.shared.clearAlert()
        return record
    }

    func connectionHealth(connectorID: String) async throws -> GmailConnectionHealthResult {'''
)

replace_once(
    gmail,
    '''            case .connected:
                GmailConnectionIssueStore.shared.clear()
                await GmailConnectionAlertManager.shared.clearAlert()
            case .disconnected(let reason):
                GmailConnectionStore.shared.invalidate(
                    connectorID: record.connectorID,
                    reason: reason
                )''',
    '''            case .connected:
                if GmailRecoveryKeychain.load(connectorID: record.connectorID) == nil {
                    try? await GmailOAuthClient.shared.cacheRecoveryBlob(
                        connectorID: record.connectorID
                    )
                }
                GmailConnectionIssueStore.shared.clear()
                await GmailConnectionAlertManager.shared.clearAlert()
            case .disconnected(let reason):
                do {
                    _ = try await GmailOAuthClient.shared.restoreConnection(
                        connectorID: record.connectorID
                    )
                    return
                } catch {
                    GmailConnectionStore.shared.invalidate(
                        connectorID: record.connectorID,
                        reason: reason
                    )
                }'''
)

# Automatic email scheduling and manual Send Email Now retry once after restoring Gmail.
email_core = SOURCES / "EmailAutomationCore.swift"
replace_once(
    email_core,
    '''                try await submit(reminder: reminder, settings: settings, testOnly: false)
                postStatus("Email automation scheduled for \\(reminder.title).")''',
    '''                try await submitWithGmailRecovery(
                    reminder: reminder,
                    settings: settings,
                    testOnly: false
                )
                postStatus("Email automation scheduled for \\(reminder.title).")'''
)
replace_once(
    email_core,
    '''                try await submit(reminder: reminder, settings: settings, testOnly: true)
            } catch {''',
    '''                try await submitWithGmailRecovery(
                    reminder: reminder,
                    settings: settings,
                    testOnly: true
                )
            } catch {'''
)
replace_once(
    email_core,
    '''            try await submit(reminder: reminder, settings: settings, testOnly: true)
            return "Test email request accepted by the scheduler."''',
    '''            try await submitWithGmailRecovery(
                reminder: reminder,
                settings: settings,
                testOnly: true
            )
            return "Test email request accepted by the scheduler."'''
)
replace_once(
    email_core,
    '''    private func submit(
        reminder: ReminderItem,
        settings: EmailAutomationSettings,
        testOnly: Bool
    ) async throws {''',
    '''    private func submitWithGmailRecovery(
        reminder: ReminderItem,
        settings: EmailAutomationSettings,
        testOnly: Bool
    ) async throws {
        do {
            try await submit(reminder: reminder, settings: settings, testOnly: testOnly)
        } catch {
            let message = error.localizedDescription
            guard settings.deliveryMethod == .gmailAutomatic,
                  GmailConnectionStore.isDisconnectionMessage(message),
                  !settings.remoteConnectorID.isEmpty else {
                throw error
            }

            _ = try await GmailOAuthClient.shared.restoreConnection(
                connectorID: settings.remoteConnectorID
            )
            try await submit(reminder: reminder, settings: settings, testOnly: testOnly)
        }
    }

    private func submit(
        reminder: ReminderItem,
        settings: EmailAutomationSettings,
        testOnly: Bool
    ) async throws {'''
)

# File sharing also restores and retries once when Render lost its connector database.
files = SOURCES / "FileSharing.swift"
replace_once(
    files,
    '''        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(FileShareServerResponse.self, from: data).message)
                ?? "File sharing failed (\\(http.statusCode))."
            throw FileShareError.server(message)
        }

        return (try? JSONDecoder().decode(FileShareServerResponse.self, from: data).message)
            ?? "Email sent successfully."''',
    '''        if !(200...299).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(FileShareServerResponse.self, from: data).message)
                ?? "File sharing failed (\\(http.statusCode))."

            if GmailConnectionStore.isDisconnectionMessage(message) {
                _ = try await GmailOAuthClient.shared.restoreConnection(
                    connectorID: gmail.connectorID
                )
                let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
                guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                    throw FileShareError.invalidResponse
                }
                guard (200...299).contains(retryHTTP.statusCode) else {
                    let retryMessage = (try? JSONDecoder().decode(FileShareServerResponse.self, from: retryData).message)
                        ?? "File sharing failed after Gmail recovery (\\(retryHTTP.statusCode))."
                    throw FileShareError.server(retryMessage)
                }
                return (try? JSONDecoder().decode(FileShareServerResponse.self, from: retryData).message)
                    ?? "Email sent successfully after restoring Gmail."
            }

            throw FileShareError.server(message)
        }

        return (try? JSONDecoder().decode(FileShareServerResponse.self, from: data).message)
            ?? "Email sent successfully."'''
)

project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.11"', 'CFBundleShortVersionString: "1.3.12"')
project_text = project_text.replace('CFBundleVersion: "21"', 'CFBundleVersion: "22"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.11"', 'MARKETING_VERSION: "1.3.12"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "21"', 'CURRENT_PROJECT_VERSION: "22"')
project.write_text(project_text)

settings_file = SOURCES / "Settings.swift"
settings_file.write_text(
    settings_file.read_text().replace(
        "Version 1.3.11 • iOS 16.0+",
        "Version 1.3.12 • iOS 16.0+"
    )
)

for path in SOURCES.glob("*.swift"):
    path.write_text(
        path.read_text().replace(
            "NextReminder-iOS/1.3.11",
            "NextReminder-iOS/1.3.12"
        )
    )

print("Next Reminder v1.3.12 Gmail automatic recovery applied successfully.")
