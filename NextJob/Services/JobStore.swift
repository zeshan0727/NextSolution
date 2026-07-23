import Foundation
import Combine
import UserNotifications

struct BackupRestoreSummary {
    var jobCount: Int
    var attachmentFileCount: Int
    var attachmentBytes: Int64
}

@MainActor
final class JobStore: ObservableObject {
    @Published private(set) var jobs: [JobRecord] = []
    @Published private(set) var settings: AppSettings = .defaults
    @Published var lastError: String?

    static let shared = JobStore()

    private let fileManager = FileManager.default
    private let databaseURL: URL
    private let persistenceQueue = DispatchQueue(
        label: "com.nextsolution.nextjob.persistence",
        qos: .utility
    )

    init() {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextJob", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        databaseURL = root.appendingPathComponent("NextJobData.json")
        load()
    }

    var sortedJobs: [JobRecord] {
        jobs.sorted {
            if $0.status == .completed, $1.status != .completed { return false }
            if $0.status != .completed, $1.status == .completed { return true }
            return $0.dueDate < $1.dueDate
        }
    }

    var summary: DashboardSummary {
        var notStarted = 0
        var inProgress = 0
        var waiting = 0
        var completed = 0
        var overdue = 0
        var completedValue = 0.0
        var outstandingValue = 0.0
        var targetMinutes = 0
        var actualMinutes = 0

        for job in jobs {
            switch job.status {
            case .notStarted: notStarted += 1
            case .inProgress: inProgress += 1
            case .waitingForDocuments: waiting += 1
            case .completed:
                completed += 1
                completedValue += job.price
            }
            if job.status != .completed { outstandingValue += job.price }
            if job.isOverdue { overdue += 1 }
            targetMinutes += job.targetMinutes
            actualMinutes += job.actualMinutes ?? 0
        }

        return DashboardSummary(
            total: jobs.count,
            notStarted: notStarted,
            inProgress: inProgress,
            waiting: waiting,
            completed: completed,
            overdue: overdue,
            completedValue: completedValue,
            outstandingValue: outstandingValue,
            targetMinutes: targetMinutes,
            actualMinutes: actualMinutes
        )
    }

    func job(id: UUID) -> JobRecord? { jobs.first { $0.id == id } }

    func save(_ job: JobRecord) {
        var updated = job
        updated.updatedAt = Date()
        if let index = jobs.firstIndex(where: { $0.id == updated.id }) {
            jobs[index] = updated
        } else {
            jobs.append(updated)
        }
        persist()
        refreshNotification(for: updated)
    }

    func delete(_ job: JobRecord) {
        jobs.removeAll { $0.id == job.id }
        NotificationService.shared.cancel(jobID: job.id)
        persist()
        let jobID = job.id
        DispatchQueue.global(qos: .utility).async {
            try? JobFileService.shared.deleteJobFolder(jobID: jobID)
        }
    }

    func setStatus(_ status: JobStatus, jobID: UUID) {
        mutate(jobID: jobID) { job in
            job.status = status
            if status == .completed {
                job.completedDate = job.completedDate ?? Date()
            } else {
                job.completedDate = nil
            }
        }
    }

    func complete(jobID: UUID, actualMinutes: Int? = nil) {
        mutate(jobID: jobID) { job in
            job.status = .completed
            job.completedDate = Date()
            if let actualMinutes { job.actualMinutes = actualMinutes }
        }
    }

    func addAttachments(_ attachments: [JobAttachment], to jobID: UUID) {
        guard !attachments.isEmpty else { return }
        mutate(jobID: jobID) { $0.attachments.append(contentsOf: attachments) }
    }

    func removeAttachment(_ attachment: JobAttachment, from jobID: UUID) {
        mutate(jobID: jobID) { $0.attachments.removeAll { $0.id == attachment.id } }
        DispatchQueue.global(qos: .utility).async {
            try? JobFileService.shared.deleteAttachment(attachment, jobID: jobID)
        }
    }

    func addEmailRecord(_ record: JobEmailRecord, to jobID: UUID) {
        mutate(jobID: jobID) { $0.emailHistory.insert(record, at: 0) }
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        var value = settings
        transform(&value)
        settings = value
        persist()
        if !settings.dueRemindersEnabled {
            NotificationService.shared.cancelAll(jobIDs: jobs.map(\.id))
        } else {
            jobs.forEach { refreshNotification(for: $0) }
        }
    }

    func addJobType(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !settings.jobTypes.contains(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) else { return }
        updateSettings { $0.jobTypes.append(JobType(name: trimmed)) }
    }

    func deleteJobTypes(at offsets: IndexSet) {
        updateSettings { settings in
            for index in offsets.sorted(by: >) where settings.jobTypes.indices.contains(index) {
                settings.jobTypes.remove(at: index)
            }
        }
    }

    func requestReminderPermission() async -> Bool {
        await NotificationService.shared.requestPermission()
    }

    func exportCompleteBackup() async throws -> URL {
        let database = AppDatabase(jobs: jobs, settings: settings)
        return try await Task.detached(priority: .userInitiated) {
            try PortableBackupService.shared.createBackup(database: database)
        }.value
    }

    func restoreCompleteBackup(from url: URL) async throws -> BackupRestoreSummary {
        let prepared = try await Task.detached(priority: .userInitiated) {
            try PortableBackupService.shared.prepareRestore(from: url)
        }.value

        let oldDatabase = AppDatabase(jobs: jobs, settings: settings)
        var previousRoot: URL?
        do {
            previousRoot = try JobFileService.shared.installRestoredRoot(from: prepared.stagingRoot)
            jobs = prepared.database.jobs
            settings = prepared.database.settings
            try persistSynchronously(prepared.database)
            JobFileService.shared.discardPreviousRoot(previousRoot)
            PortableBackupService.shared.discard(prepared)
            jobs.forEach { refreshNotification(for: $0) }
            return BackupRestoreSummary(
                jobCount: jobs.count,
                attachmentFileCount: prepared.fileCount,
                attachmentBytes: prepared.totalBytes
            )
        } catch {
            JobFileService.shared.rollbackRestoredRoot(previousRoot: previousRoot)
            jobs = oldDatabase.jobs
            settings = oldDatabase.settings
            try? persistSynchronously(oldDatabase)
            PortableBackupService.shared.discard(prepared)
            throw error
        }
    }

    func exportDatabase() throws -> URL {
        let payload = AppDatabase(jobs: jobs, settings: settings)
        let data = try makeEncoder().encode(payload)
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("NextJob-Legacy-Backup-\(Self.exportDateFormatter.string(from: Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func importDatabase(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoded = try makeDecoder().decode(AppDatabase.self, from: data)
        jobs = decoded.jobs
        settings = decoded.settings
        try persistSynchronously(decoded)
        jobs.forEach { refreshNotification(for: $0) }
    }

    private func mutate(jobID: UUID, _ transform: (inout JobRecord) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        transform(&jobs[index])
        jobs[index].updatedAt = Date()
        let updated = jobs[index]
        persist()
        refreshNotification(for: updated)
    }

    private func load() {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            jobs = []
            settings = .defaults
            return
        }
        do {
            let data = try Data(contentsOf: databaseURL)
            let database = try makeDecoder().decode(AppDatabase.self, from: data)
            jobs = database.jobs
            settings = database.settings
        } catch {
            lastError = "Your saved data could not be opened: \(error.localizedDescription)"
            jobs = []
            settings = .defaults
        }
    }

    private func persist() {
        let database = AppDatabase(jobs: jobs, settings: settings)
        let url = databaseURL
        persistenceQueue.async { [weak self] in
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(database)
                try data.write(to: url, options: .atomic)
            } catch {
                let message = "Next Job could not save your changes: \(error.localizedDescription)"
                DispatchQueue.main.async {
                    self?.lastError = message
                }
            }
        }
    }

    private func persistSynchronously(_ database: AppDatabase) throws {
        let data = try makeEncoder().encode(database)
        try data.write(to: databaseURL, options: .atomic)
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func refreshNotification(for job: JobRecord) {
        guard settings.dueRemindersEnabled, job.status != .completed else {
            NotificationService.shared.cancel(jobID: job.id)
            return
        }
        NotificationService.shared.schedule(for: job)
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}

final class NotificationService {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func schedule(for job: JobRecord) {
        cancel(jobID: job.id)
        for (label, offset) in [("24h", -86_400.0), ("1h", -3_600.0)] {
            let date = job.dueDate.addingTimeInterval(offset)
            guard date > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Job deadline approaching"
            content.body = "\(job.title) is due \(label == "24h" ? "tomorrow" : "in one hour")."
            content.sound = .default
            let parts = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
            let request = UNNotificationRequest(
                identifier: "nextjob-\(job.id.uuidString)-\(label)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            center.add(request)
        }
    }

    func cancel(jobID: UUID) {
        let prefix = "nextjob-\(jobID.uuidString)-"
        center.getPendingNotificationRequests { [center] requests in
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func cancelAll(jobIDs: [UUID]) {
        jobIDs.forEach { cancel(jobID: $0) }
    }
}
