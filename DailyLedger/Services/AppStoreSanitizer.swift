import Foundation

enum AppStoreSanitizer {
    static func sanitizeLegacySettings() {
        do {
            _ = try LedgerDiskStore.shared.mutate { ledger in
                ledger.settings.smsAutoImportEnabled = false
                ledger.settings.smsMatchText = ""
                ledger.settings.smsDestinationAccountID = nil
                ledger.settings.smsRescanRequestID = 0
                ledger.settings.smsImporterLastCheck = nil
                ledger.settings.smsImporterLastResult = nil
            }
        } catch {
            // Legacy settings are nonessential to the App Store build.
        }
    }
}
