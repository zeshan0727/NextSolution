import Foundation

extension EmailAutomationSettings {
    var fullyConfigured: Bool {
        guard hasValidRecipient else { return false }
        guard deliveryMethod.isAutomatic else { return true }

        if deliveryMethod == .gmailAutomatic {
            guard let connection = GmailConnectionStore.shared.load() else { return false }
            return !remoteConnectorID.isEmpty && connection.connectorID == remoteConnectorID
        }

        return automaticConnectorReady
    }
}
