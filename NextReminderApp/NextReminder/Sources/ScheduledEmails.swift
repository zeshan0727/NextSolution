import Foundation
import SwiftUI

// MARK: - Standalone recurring email schedules
// These are intentionally separate from ReminderItem and never appear in Reminders/Completed.
enum ScheduledEmailFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case quarterly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .quarterly: return "Quarterly"
        }
    }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: date)
        }
    }
}

struct ScheduledEmailItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var recipient: String
    var subject: String
    var body: String
    var firstSendAt: Date
    var frequency: ScheduledEmailFrequency
    var isEnabled: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var hasValidRecipient: Bool {
        let cleaned = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = cleaned.firstIndex(of: "@") else { return false }
        return cleaned[cleaned.index(after: at)...].contains(".")
    }

    var nextOccurrence: Date? {
        var candidate = firstSendAt
        let now = Date()
        var guardCount = 0
        while candidate <= now && guardCount < 5000 {
            guard let next = frequency.nextDate(after: candidate) else { return nil }
            candidate = next
            guardCount += 1
        }
        return candidate
    }
}

@MainActor
final class ScheduledEmailStore: ObservableObject {
    static let defaultsKey = "NextReminder.ScheduledEmails.v1"

    @Published private(set) var items: [ScheduledEmailItem] = []
    @Published var statusMessage: String?
    @Published var isSyncing = false

    init() {
        load()
        // Replenish the remote horizon when the app is opened. This never creates
        // ReminderItem records and therefore cannot leak into the reminder list.
        let enabled = items.filter(\.isEnabled)
        if !enabled.isEmpty {
            Task { await syncAll(enabled) }
        }
    }

    func add(_ item: ScheduledEmailItem) {
        var value = item
        value.createdAt = Date()
        value.updatedAt = Date()
        items.append(value)
        persist()
        Task { await sync(value) }
    }

    func update(_ item: ScheduledEmailItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let old = items[index]
        var value = item
        value.updatedAt = Date()
        items[index] = value
        persist()
        Task {
            await ScheduledEmailRemoteManager.shared.cancel(old)
            await sync(value)
        }
    }

    func delete(_ item: ScheduledEmailItem) {
        items.removeAll { $0.id == item.id }
        persist()
        Task {
            await ScheduledEmailRemoteManager.shared.cancel(item)
            statusMessage = "Email schedule deleted and future deliveries cancelled."
        }
    }

    func setEnabled(_ enabled: Bool, for item: ScheduledEmailItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isEnabled = enabled
        items[index].updatedAt = Date()
        let value = items[index]
        persist()
        Task {
            if enabled {
                await sync(value)
            } else {
                await ScheduledEmailRemoteManager.shared.cancel(value)
                statusMessage = "Email schedule paused."
            }
        }
    }

    func refresh() {
        let enabled = items.filter(\.isEnabled)
        Task { await syncAll(enabled) }
    }

    private func sync(_ item: ScheduledEmailItem) async {
        guard item.isEnabled else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await ScheduledEmailRemoteManager.shared.sync(item)
            statusMessage = result
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func syncAll(_ enabled: [ScheduledEmailItem]) async {
        guard !enabled.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }
        for item in enabled {
            do {
                statusMessage = try await ScheduledEmailRemoteManager.shared.sync(item)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([ScheduledEmailItem].self, from: data) else {
            items = []
            return
        }
        items = decoded.sorted { ($0.nextOccurrence ?? .distantFuture) < ($1.nextOccurrence ?? .distantFuture) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

private enum ScheduledEmailRemoteError: LocalizedError {
    case disabled
    case invalidRecipient
    case missingConnector
    case schedulerNotConfigured
    case invalidEndpoint
    case server(String)

    var errorDescription: String? {
        switch self {
        case .disabled: return "Enable email automation in Email Reminder Automations first."
        case .invalidRecipient: return "Enter a valid recipient email address."
        case .missingConnector: return "Configure the Gmail, iCloud, or SMTP connector first."
        case .schedulerNotConfigured: return "Configure the HTTPS automation scheduler first."
        case .invalidEndpoint: return "The scheduler URL must be a valid HTTPS address."
        case .server(let message): return message
        }
    }
}

private final class ScheduledEmailRemoteManager {
    static let shared = ScheduledEmailRemoteManager()
    private let schedulerEndpointKey = "NextReminder.AutomationCloudEndpoint"
    private let horizonDays: TimeInterval = 366
    private init() {}

    func sync(_ item: ScheduledEmailItem) async throws -> String {
        let settings = EmailAutomationSettings.load()
        guard settings.enabled else { throw ScheduledEmailRemoteError.disabled }
        guard item.hasValidRecipient else { throw ScheduledEmailRemoteError.invalidRecipient }
        guard settings.deliveryMethod.isAutomatic else {
            throw ScheduledEmailRemoteError.server("Recurring email schedules require Gmail, iCloud, or SMTP Automatic mode.")
        }
        guard settings.automaticConnectorReady else { throw ScheduledEmailRemoteError.missingConnector }

        // Prefer a true recurring server job when the scheduler supports it.
        if try await submitRecurring(item, settings: settings) {
            return "\(item.frequency.title) email schedule is active automatically."
        }

        // Backward-compatible fallback for existing schedulers: pre-schedule one
        // full year of individual jobs, then replenish that horizon whenever the
        // app is opened. This keeps the feature automatic without mixing it into reminders.
        let dates = occurrenceDates(for: item)
        try await submitOccurrences(item, dates: dates, settings: settings)
        let end = dates.last?.formatted(date: .abbreviated, time: .omitted) ?? "the next year"
        return "\(item.frequency.title) email schedule synced through \(end)."
    }

    func cancel(_ item: ScheduledEmailItem) async {
        // New scheduler route, when available.
        _ = try? await sendJSON(
            path: "v1/email-schedules/cancel",
            body: ["scheduleID": item.id.uuidString]
        )

        // Existing scheduler fallback: cancel deterministic one-time occurrence IDs.
        let dates = occurrenceDates(for: item, includePastHorizon: true)
        for chunkStart in stride(from: 0, to: dates.count, by: 16) {
            let upper = min(chunkStart + 16, dates.count)
            await withTaskGroup(of: Void.self) { group in
                for date in dates[chunkStart..<upper] {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        let localID = self.occurrenceID(item: item, date: date)
                        _ = try? await self.sendJSON(
                            path: "v1/email-reminders/cancel",
                            body: ["localID": localID]
                        )
                    }
                }
            }
        }
    }

    private func submitRecurring(_ item: ScheduledEmailItem, settings: EmailAutomationSettings) async throws -> Bool {
        let payload = ScheduledEmailRecurringPayload(
            scheduleID: item.id.uuidString,
            recipient: item.recipient.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: settings.deliveryMethod.providerKey,
            remoteConnectorID: settings.remoteConnectorID,
            senderLabel: settings.senderLabel,
            subject: item.subject,
            body: item.body,
            firstSendAt: ISO8601DateFormatter().string(from: item.nextOccurrence ?? item.firstSendAt),
            frequency: item.frequency.rawValue,
            timeZone: TimeZone.current.identifier,
            enabled: item.isEnabled
        )

        do {
            let response = try await sendEncodable(path: "v1/email-schedules", body: payload)
            return (200...299).contains(response)
        } catch ScheduledEmailRemoteError.server(let message) {
            // 404/405/unsupported route: use the compatible one-time scheduler fallback.
            let lower = message.lowercased()
            if lower.contains("404") || lower.contains("405") || lower.contains("not found") || lower.contains("unsupported") {
                return false
            }
            throw ScheduledEmailRemoteError.server(message)
        }
    }

    private func submitOccurrences(
        _ item: ScheduledEmailItem,
        dates: [Date],
        settings: EmailAutomationSettings
    ) async throws {
        for chunkStart in stride(from: 0, to: dates.count, by: 12) {
            let upper = min(chunkStart + 12, dates.count)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for date in dates[chunkStart..<upper] {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        let payload = ScheduledEmailOccurrencePayload(
                            localID: self.occurrenceID(item: item, date: date),
                            recipient: item.recipient.trimmingCharacters(in: .whitespacesAndNewlines),
                            provider: settings.deliveryMethod.providerKey,
                            remoteConnectorID: settings.remoteConnectorID,
                            senderLabel: settings.senderLabel,
                            subject: item.subject,
                            body: item.body,
                            scheduledAt: ISO8601DateFormatter().string(from: date),
                            timeZone: TimeZone.current.identifier,
                            reminderTitle: item.name,
                            reminderTime: ISO8601DateFormatter().string(from: date),
                            deadline: nil,
                            testOnly: false
                        )
                        _ = try await self.sendEncodable(path: "v1/email-reminders", body: payload)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    private func occurrenceDates(for item: ScheduledEmailItem, includePastHorizon: Bool = false) -> [Date] {
        let now = Date()
        let startBoundary = includePastHorizon
            ? Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            : now
        let end = Calendar.current.date(byAdding: .day, value: Int(horizonDays), to: now)
            ?? now.addingTimeInterval(horizonDays * 86_400)

        var current = item.firstSendAt
        var dates: [Date] = []
        var guardCount = 0
        while current <= end && guardCount < 5000 {
            if current >= startBoundary { dates.append(current) }
            guard let next = item.frequency.nextDate(after: current) else { break }
            current = next
            guardCount += 1
        }
        return dates
    }

    private func occurrenceID(item: ScheduledEmailItem, date: Date) -> String {
        "email-schedule-\(item.id.uuidString)-\(Int(date.timeIntervalSince1970))"
    }

    private func makeRequest(path: String) throws -> URLRequest {
        let endpoint = UserDefaults.standard.string(forKey: schedulerEndpointKey) ?? ""
        let apiKey = AutomationKeychain.load()
        guard !endpoint.isEmpty, !apiKey.isEmpty else {
            throw ScheduledEmailRemoteError.schedulerNotConfigured
        }
        let normalized = endpoint.hasSuffix("/") ? endpoint : endpoint + "/"
        guard let base = URL(string: normalized),
              base.scheme?.lowercased() == "https",
              let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw ScheduledEmailRemoteError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("NextReminder-iOS/1.3.19", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func sendJSON(path: String, body: [String: String]) async throws -> Int {
        var request = try makeRequest(path: path)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        return try validate(response, data: data)
    }

    private func sendEncodable<T: Encodable>(path: String, body: T) async throws -> Int {
        var request = try makeRequest(path: path)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        return try validate(response, data: data)
    }

    private func validate(_ response: URLResponse, data: Data) throws -> Int {
        guard let http = response as? HTTPURLResponse else {
            throw ScheduledEmailRemoteError.server("Email scheduler returned an invalid response.")
        }
        guard (200...299).contains(http.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ScheduledEmailRemoteError.server(
                serverMessage?.isEmpty == false ? serverMessage! : "Email scheduler request failed (\(http.statusCode))."
            )
        }
        return http.statusCode
    }
}

private struct ScheduledEmailRecurringPayload: Encodable {
    var scheduleID: String
    var recipient: String
    var provider: String
    var remoteConnectorID: String
    var senderLabel: String
    var subject: String
    var body: String
    var firstSendAt: String
    var frequency: String
    var timeZone: String
    var enabled: Bool
}

private struct ScheduledEmailOccurrencePayload: Encodable {
    var localID: String
    var recipient: String
    var provider: String
    var remoteConnectorID: String
    var senderLabel: String
    var subject: String
    var body: String
    var scheduledAt: String
    var timeZone: String
    var reminderTitle: String
    var reminderTime: String
    var deadline: String?
    var testOnly: Bool
}

struct EmailSchedulesView: View {
    @EnvironmentObject private var store: ScheduledEmailStore
    @State private var editingItem: ScheduledEmailItem?
    @State private var showNew = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatic Email Schedules")
                            .font(.title2.bold())
                        Text("Separate from reminders • Daily, weekly or quarterly")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "envelope.arrow.triangle.branch.fill")
                        .font(.title2)
                        .foregroundStyle(.nextOrange)
                }
                .padding(.top, 8)

                if let message = store.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 12))
                }

                if store.items.isEmpty {
                    EmptyStateView(
                        icon: "envelope.badge.clock.fill",
                        title: "No email schedules",
                        message: "Create an automatic email that repeats daily, weekly or quarterly. These schedules never appear in your reminders list."
                    )
                } else {
                    ForEach(store.items) { item in
                        Button { editingItem = item } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "envelope.fill")
                                    .foregroundStyle(item.isEnabled ? Color.nextOrange : Color.secondary)
                                    .frame(width: 42, height: 42)
                                    .background(Color.nextOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.headline).foregroundStyle(.primary)
                                    Text("\(item.frequency.title) • \(item.recipient)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if let next = item.nextOccurrence {
                                        Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { item.isEnabled },
                                    set: { store.setEnabled($0, for: item) }
                                ))
                                .labelsHidden()
                                .onTapGesture { }
                            }
                            .padding(14)
                            .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { editingItem = item } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) { store.delete(item) } label: {
                                Label("Delete Schedule", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("Email Schedules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack { EmailScheduleEditorView(item: nil) }
                .environmentObject(store)
        }
        .sheet(item: $editingItem) { item in
            NavigationStack { EmailScheduleEditorView(item: item) }
                .environmentObject(store)
        }
    }
}

struct EmailScheduleEditorView: View {
    @EnvironmentObject private var store: ScheduledEmailStore
    @Environment(\.dismiss) private var dismiss
    let item: ScheduledEmailItem?

    @State private var name: String
    @State private var recipient: String
    @State private var subject: String
    @State private var bodyText: String
    @State private var firstSendAt: Date
    @State private var frequency: ScheduledEmailFrequency
    @State private var isEnabled: Bool

    init(item: ScheduledEmailItem?) {
        self.item = item
        let emailSettings = EmailAutomationSettings.load()
        _name = State(initialValue: item?.name ?? "")
        _recipient = State(initialValue: item?.recipient ?? emailSettings.recipient)
        _subject = State(initialValue: item?.subject ?? "Scheduled email")
        _bodyText = State(initialValue: item?.body ?? "")
        _firstSendAt = State(initialValue: item?.firstSendAt ?? Date().addingTimeInterval(300))
        _frequency = State(initialValue: item?.frequency ?? .weekly)
        _isEnabled = State(initialValue: item?.isEnabled ?? true)
    }

    private var canSave: Bool {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanedName.isEmpty && cleanedRecipient.contains("@") && cleanedRecipient.contains(".")
            && !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Schedule") {
                TextField("Schedule name", text: $name)
                Picker("Repeat", selection: $frequency) {
                    ForEach(ScheduledEmailFrequency.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                DatePicker("First send", selection: $firstSendAt)
                Toggle("Enabled", isOn: $isEnabled)
            }

            Section("Email") {
                TextField("Recipient", text: $recipient)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Subject", text: $subject)
                TextEditor(text: $bodyText)
                    .frame(minHeight: 150)
            }

            Section {
                Text("This is a standalone email schedule. It will not create a normal reminder and will not appear in Reminders or Completed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(item == nil ? "New Email Schedule" : "Edit Email Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
    }

    private func save() {
        let value = ScheduledEmailItem(
            id: item?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            recipient: recipient.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            body: bodyText,
            firstSendAt: firstSendAt,
            frequency: frequency,
            isEnabled: isEnabled,
            createdAt: item?.createdAt ?? Date(),
            updatedAt: Date()
        )
        if item == nil { store.add(value) } else { store.update(value) }
        dismiss()
    }
}
