import Foundation
import Combine
import UserNotifications

@MainActor
final class JobStore: ObservableObject {
    @Published private(set) var jobs: [JobRecord] = []
    @Published private(set) var settings: AppSettings = .defaults
    @Published var lastError: String?

    static let shared = JobStore()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let databaseURL: URL

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

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
        DashboardSummary(
            total: jobs.count,
            notStarted: jobs.filter { $0.status == .notStarted }.count,
            inProgress: jobs.filter { $0.status == .inProgress }.count,
            waiting: jobs.filter { $0.status == .waitingForDocuments }.count,
            completed: jobs.filter { $0.status == .completed }.count,
            overdue: jobs.filter(\.isOverdue).count,
            completedValue: jobs.filter { $0.status == .completed }.reduce(0) { $0 + $1.price },
            outstandingValue: jobs.filter { $0.status != .completed }.reduce(0) { $0 + $1.price },
            targetMinutes: jobs.reduce(0) { $0 + $1.targetMinutes },
            actualMinutes: jobs.compactMap(\.actualMinutes).reduce(0, +)
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
        try? JobFileService.shared.deleteJobFolder(jobID: job.id)
        NotificationService.shared.cancel(jobID: job.id)
        persist()
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
        mutate(jobID: jobID) { $0.attachments.append(contentsOf: attachments) }
    }

    func removeAttachment(_ attachment: JobAttachment, from jobID: UUID) {
        mutate(jobID: jobID) { $0.attachments.removeAll { $0.id == attachment.id } }
        try? JobFileService.shared.deleteAttachment(attachment, jobID: jobID)
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
        guard !settings.jobTypes.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
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

    func exportDatabase() throws -> URL {
        let payload = AppDatabase(jobs: jobs, settings: settings)
        let data = try encoder.encode(payload)
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("NextJob-Backup-\(Self.exportDateFormatter.string(from: Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func importDatabase(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoded = try decoder.decode(AppDatabase.self, from: data)
        jobs = decoded.jobs
        settings = decoded.settings
        persist()
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
            let database = try decoder.decode(AppDatabase.self, from: data)
            jobs = database.jobs
            settings = database.settings
        } catch {
            lastError = "Your saved data could not be opened: \(error.localizedDescription)"
            jobs = []
            settings = .defaults
        }
    }

    private func persist() {
        do {
            let database = AppDatabase(jobs: jobs, settings: settings)
            let data = try encoder.encode(database)
            try data.write(to: databaseURL, options: .atomic)
        } catch {
            lastError = "Next Job could not save your changes: \(error.localizedDescription)"
        }
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
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
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
