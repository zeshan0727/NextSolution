import BackgroundTasks
import Combine
import Foundation
import UIKit

final class BackupSyncService: ObservableObject {
    static let shared = BackupSyncService()
    static let taskIdentifier = "com.nextsolution.dailyledger.backup-refresh"

    @Published private(set) var status = "Local automatic backup is ready."
    @Published private(set) var lastBackupDate: Date?

    private init() {
        if let date = UserDefaults.standard.object(forKey: "DailyLedgerLastBackupDate") as? Date {
            lastBackupDate = date
        }
    }

    func ledgerDidSave(_ data: Data) {
        DispatchQueue.main.async {
            self.saveSnapshot(data, includeICloud: UserDefaults.standard.bool(forKey: "DailyLedgerICloudSync"))
        }
    }

    func syncNow(ledger: LedgerData) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(ledger) else {
            status = "Backup could not be encoded."
            return
        }
        saveSnapshot(data, includeICloud: true)
    }

    func restoreLatestICloudBackup() throws -> LedgerData {
        guard let url = iCloudBackupURL,
              FileManager.default.fileExists(atPath: url.path) else {
            throw BackupSyncError.iCloudBackupUnavailable
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LedgerData.self, from: data)
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func handleDidEnterBackground(ledger: LedgerData) {
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "DailyLedgerBackup") {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }
        syncNow(ledger: ledger)
        scheduleBackgroundRefresh()
        if taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                self.syncNow(ledger: LedgerDiskStore.shared.load())
                refresh.setTaskCompleted(success: true)
                self.scheduleBackgroundRefresh()
            }
        }
    }

    private func saveSnapshot(_ data: Data, includeICloud: Bool) {
        do {
            let directory = localBackupURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: localBackupURL, options: .atomic)
            lastBackupDate = Date()
            UserDefaults.standard.set(lastBackupDate, forKey: "DailyLedgerLastBackupDate")

            guard includeICloud else {
                status = "Local backup saved automatically."
                return
            }
            guard let cloudURL = iCloudBackupURL else {
                status = "Local backup saved. Automatic iCloud requires an Apple-provisioned iCloud entitlement."
                return
            }
            try FileManager.default.createDirectory(
                at: cloudURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cloudURL, options: .atomic)
            status = "Local and iCloud Drive backups are up to date."
        } catch {
            status = "Backup failed: \(error.localizedDescription)"
        }
    }

    private var localBackupURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DailyLedger/Backups", isDirectory: true)
            .appendingPathComponent("Latest-DailyLedger-Backup.json")
    }

    private var iCloudBackupURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents/DailyLedger", isDirectory: true)
            .appendingPathComponent("Latest-DailyLedger-Backup.json")
    }
}

enum BackupSyncError: LocalizedError {
    case iCloudBackupUnavailable

    var errorDescription: String? {
        "No DailyLedger backup is available in iCloud Drive, or this TrollStore build has no iCloud entitlement."
    }
}
