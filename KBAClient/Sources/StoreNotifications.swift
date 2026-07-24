// MARK: - Sources/Services/AppStore.swift
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var profile: UserProfile?
    @Published private(set) var requests: [ClientRequest] = []
    @Published private(set) var consultations: [ConsultationRequest] = []
    @Published private(set) var documents: [ImportedDocument] = []

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        let applicationSupport = baseDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.baseDirectory = applicationSupport.appendingPathComponent("KBAClient", isDirectory: true)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        prepareDirectories()
        loadAll()
    }

    func completeOnboarding(_ newProfile: UserProfile) {
        profile = newProfile
        save(newProfile, as: "profile.json")
    }

    func updateProfile(_ updatedProfile: UserProfile) {
        profile = updatedProfile
        save(updatedProfile, as: "profile.json")
    }

    @discardableResult
    func addRequest(
        service: KBAService,
        jurisdiction: Jurisdiction,
        companyName: String,
        details: String,
        priority: RequestPriority,
        preferredContact: ContactMethod
    ) -> ClientRequest {
        let createdAt = Date()
        let request = ClientRequest(
            id: UUID(),
            reference: Self.makeReference(date: createdAt),
            serviceID: service.id,
            serviceName: service.title,
            createdAt: createdAt,
            jurisdiction: jurisdiction,
            companyName: companyName,
            details: details,
            priority: priority,
            preferredContact: preferredContact,
            status: .submitted,
            timeline: [StatusEvent(status: .submitted, date: createdAt, note: AppConfiguration.isLocalTestMode ? "Saved locally for testing. Not yet sent to KBA." : "Request received.")]
        )
        requests.insert(request, at: 0)
        save(requests, as: "requests.json")
        return request
    }

    func addConsultation(date: Date, contactMethod: ContactMethod, topic: String, notes: String) {
        let consultation = ConsultationRequest(
            id: UUID(),
            requestedDate: date,
            contactMethod: contactMethod,
            topic: topic,
            notes: notes,
            createdAt: Date()
        )
        consultations.insert(consultation, at: 0)
        save(consultations, as: "consultations.json")
    }

    func importDocument(from sourceURL: URL, category: DocumentCategory) throws {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let id = UUID()
        let safeName = sourceURL.lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let localName = "\(id.uuidString)-\(safeName)"
        let destination = documentsDirectory.appendingPathComponent(localName)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)

        let attributes = try fileManager.attributesOfItem(atPath: destination.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let document = ImportedDocument(
            id: id,
            displayName: safeName,
            localFileName: localName,
            addedAt: Date(),
            category: category,
            sizeBytes: size
        )
        documents.insert(document, at: 0)
        save(documents, as: "documents.json")
    }

    func deleteDocument(_ document: ImportedDocument) {
        let fileURL = documentsDirectory.appendingPathComponent(document.localFileName)
        try? fileManager.removeItem(at: fileURL)
        documents.removeAll { $0.id == document.id }
        save(documents, as: "documents.json")
    }

    func loadTestData() {
        guard requests.isEmpty else { return }
        let service = ServiceCatalog.all[3]
        let now = Date()
        let request = ClientRequest(
            id: UUID(),
            reference: Self.makeReference(date: now),
            serviceID: service.id,
            serviceName: service.title,
            createdAt: now,
            jurisdiction: .qatar,
            companyName: profile?.companyName ?? "Demo Company",
            details: "Demo request used to verify the request list and status timeline.",
            priority: .normal,
            preferredContact: .whatsapp,
            status: .underReview,
            timeline: [
                StatusEvent(status: .submitted, date: now.addingTimeInterval(-7_200), note: "Test request saved."),
                StatusEvent(status: .underReview, date: now.addingTimeInterval(-3_600), note: "Demo status for interface verification.")
            ]
        )
        requests = [request]
        save(requests, as: "requests.json")
    }

    func deleteAllLocalData() {
        try? fileManager.removeItem(at: baseDirectory)
        prepareDirectories()
        profile = nil
        requests = []
        consultations = []
        documents = []
    }

    static func makeReference(date: Date = Date(), suffix: Int? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        let number = suffix ?? Int.random(in: 1000...9999)
        return "KBA-\(formatter.string(from: date))-\(number)"
    }

    private var documentsDirectory: URL {
        baseDirectory.appendingPathComponent("Documents", isDirectory: true)
    }

    private func prepareDirectories() {
        try? fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
    }

    private func fileURL(named name: String) -> URL {
        baseDirectory.appendingPathComponent(name)
    }

    private func save<T: Encodable>(_ value: T, as fileName: String) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: fileURL(named: fileName), options: .atomic)
        } catch {
            assertionFailure("KBA local save failed: \(error.localizedDescription)")
        }
    }

    private func load<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        let url = fileURL(named: fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func loadAll() {
        profile = load(UserProfile.self, from: "profile.json")
        requests = load([ClientRequest].self, from: "requests.json") ?? []
        consultations = load([ConsultationRequest].self, from: "consultations.json") ?? []
        documents = load([ImportedDocument].self, from: "documents.json") ?? []
    }
}

// MARK: - Sources/Services/NotificationManager.swift
import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func scheduleConsultationReminder(for date: Date, topic: String) async {
        let reminderDate = date.addingTimeInterval(-3_600)
        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "KBA consultation reminder"
        content.body = topic.isEmpty ? "Your requested consultation is in one hour." : "\(topic) is scheduled in one hour."
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
