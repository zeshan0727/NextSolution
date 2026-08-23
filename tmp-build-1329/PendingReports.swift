import Foundation
import SwiftUI
import UIKit

// MARK: - Manual Pending Reminder PDF Reports

struct PendingReminderPDFReport: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let fileName: String
    let createdAt: Date
    let reminderCount: Int
    let byteCount: Int

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

enum PendingReminderPDFReportError: LocalizedError {
    case noPendingReminders
    case reportsDirectoryUnavailable
    case pdfCreationFailed
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPendingReminders:
            return "There are no pending reminders to include in the PDF report."
        case .reportsDirectoryUnavailable:
            return "Next Reminder could not create its local Pending Reminder Reports folder."
        case .pdfCreationFailed:
            return "The pending-reminders PDF could not be generated."
        case .saveFailed(let message):
            return "The PDF could not be saved locally: \(message)"
        }
    }
}

enum PendingReminderPDFReportService {
    private static let folderName = "Pending Reminder Reports"
    private static let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let margin: CGFloat = 42

    static func generate(
        reminders: [ReminderItem],
        defaultRecipient: String
    ) throws -> PendingReminderPDFReport {
        let pending = reminders
            .filter { !$0.isCompleted }
            .sorted { $0.effectiveDeadline < $1.effectiveDeadline }
        guard !pending.isEmpty else { throw PendingReminderPDFReportError.noPendingReminders }

        let now = Date()
        let data = renderPDF(reminders: pending, generatedAt: now, defaultRecipient: defaultRecipient)
        guard !data.isEmpty else { throw PendingReminderPDFReportError.pdfCreationFailed }

        let directory = try reportsDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "Pending-Reminders-\(formatter.string(from: now))-\(pending.count).pdf"
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw PendingReminderPDFReportError.saveFailed(error.localizedDescription)
        }

        let report = PendingReminderPDFReport(
            id: stableID(for: url),
            url: url,
            fileName: fileName,
            createdAt: now,
            reminderCount: pending.count,
            byteCount: data.count
        )
        pruneToLatestThree()
        return report
    }

    static func savedReports() -> [PendingReminderPDFReport] {
        guard let directory = try? reportsDirectory() else { return [] }
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let reports = urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .compactMap { url -> PendingReminderPDFReport? in
                let values = try? url.resourceValues(forKeys: keys)
                let created = values?.creationDate ?? values?.contentModificationDate ?? Date.distantPast
                return PendingReminderPDFReport(
                    id: stableID(for: url),
                    url: url,
                    fileName: url.lastPathComponent,
                    createdAt: created,
                    reminderCount: reminderCount(from: url.lastPathComponent),
                    byteCount: values?.fileSize ?? 0
                )
            }
            .sorted { $0.createdAt > $1.createdAt }

        return Array(reports.prefix(3))
    }

    private static func pruneToLatestThree() {
        guard let directory = try? reportsDirectory() else { return }
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        let sortedPDFs = urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { left, right in
                let lv = try? left.resourceValues(forKeys: keys)
                let rv = try? right.resourceValues(forKeys: keys)
                let ld = lv?.creationDate ?? lv?.contentModificationDate ?? .distantPast
                let rd = rv?.creationDate ?? rv?.contentModificationDate ?? .distantPast
                return ld > rd
            }

        for url in sortedPDFs.dropFirst(3) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func reportsDirectory() throws -> URL {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw PendingReminderPDFReportError.reportsDirectoryUnavailable
        }
        let directory = documents.appendingPathComponent(folderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw PendingReminderPDFReportError.saveFailed(error.localizedDescription)
        }
        return directory
    }

    private static func reminderCount(from fileName: String) -> Int {
        let base = (fileName as NSString).deletingPathExtension
        guard let suffix = base.split(separator: "-").last else { return 0 }
        return Int(suffix) ?? 0
    }

    private static func stableID(for url: URL) -> UUID {
        let bytes = Array(url.path.utf8)
        var a: UInt64 = 0xcbf29ce484222325
        var b: UInt64 = 0x84222325cbf29ce4
        for byte in bytes {
            a ^= UInt64(byte)
            a &*= 0x100000001b3
            b ^= UInt64(byte &+ 31)
            b &*= 0x100000001b3
        }
        let raw = String(
            format: "%08X-%04X-%04X-%04X-%012llX",
            UInt32(truncatingIfNeeded: a >> 32),
            UInt16(truncatingIfNeeded: a >> 16),
            UInt16(truncatingIfNeeded: a),
            UInt16(truncatingIfNeeded: b >> 48),
            b & 0x0000FFFFFFFFFFFF
        )
        return UUID(uuidString: raw) ?? UUID()
    }

    private static func renderPDF(
        reminders: [ReminderItem],
        generatedAt: Date,
        defaultRecipient: String
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        return renderer.pdfData { context in
            var pageNumber = 0
            var y: CGFloat = 0

            func beginPage() {
                context.beginPage()
                pageNumber += 1
                y = margin
                drawText(
                    "NEXT REMINDER",
                    in: CGRect(x: margin, y: y, width: pageBounds.width - margin * 2, height: 22),
                    font: .systemFont(ofSize: 11, weight: .bold),
                    color: .secondaryLabel,
                    alignment: .left
                )
                drawText(
                    "Page \(pageNumber)",
                    in: CGRect(x: margin, y: y, width: pageBounds.width - margin * 2, height: 22),
                    font: .systemFont(ofSize: 10, weight: .medium),
                    color: .secondaryLabel,
                    alignment: .right
                )
                y += 27
            }

            func ensureSpace(_ height: CGFloat) {
                if y + height > pageBounds.height - margin - 24 { beginPage() }
            }

            beginPage()
            drawText(
                "Pending Reminders Report",
                in: CGRect(x: margin, y: y, width: pageBounds.width - margin * 2, height: 38),
                font: .systemFont(ofSize: 25, weight: .bold),
                color: .label,
                alignment: .left
            )
            y += 42

            drawText(
                "Generated \(dateFormatter.string(from: generatedAt))",
                in: CGRect(x: margin, y: y, width: pageBounds.width - margin * 2, height: 20),
                font: .systemFont(ofSize: 11),
                color: .secondaryLabel,
                alignment: .left
            )
            y += 23

            let recipientText = validEmail(defaultRecipient)
                ? "Preset recipient: \(defaultRecipient)"
                : "Preset recipient: Not configured"
            drawText(
                recipientText,
                in: CGRect(x: margin, y: y, width: pageBounds.width - margin * 2, height: 20),
                font: .systemFont(ofSize: 11, weight: .medium),
                color: .secondaryLabel,
                alignment: .left
            )
            y += 30

            let summaryRect = CGRect(x: margin, y: y, width: pageBounds.width - margin * 2, height: 54)
            UIColor.secondarySystemBackground.setFill()
            UIBezierPath(roundedRect: summaryRect, cornerRadius: 12).fill()
            drawText(
                "\(reminders.count)",
                in: CGRect(x: summaryRect.minX + 16, y: summaryRect.minY + 8, width: 70, height: 27),
                font: .systemFont(ofSize: 22, weight: .bold),
                color: .label,
                alignment: .left
            )
            drawText(
                "pending reminders",
                in: CGRect(x: summaryRect.minX + 16, y: summaryRect.minY + 32, width: 180, height: 16),
                font: .systemFont(ofSize: 10, weight: .medium),
                color: .secondaryLabel,
                alignment: .left
            )
            let overdueCount = reminders.filter { $0.dueDate <= generatedAt }.count
            drawText(
                "\(overdueCount) overdue",
                in: CGRect(x: summaryRect.maxX - 155, y: summaryRect.minY + 17, width: 135, height: 20),
                font: .systemFont(ofSize: 12, weight: .semibold),
                color: overdueCount > 0 ? .systemRed : .systemGreen,
                alignment: .right
            )
            y += 72

            for (index, reminder) in reminders.enumerated() {
                let notes = reminder.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                let noteHeight = notes.isEmpty ? CGFloat(0) : textHeight(
                    notes,
                    width: pageBounds.width - margin * 2 - 28,
                    font: .systemFont(ofSize: 10.5)
                ) + 9
                ensureSpace(CGFloat(76) + noteHeight)

                let overdue = reminder.dueDate <= generatedAt
                drawText(
                    "\(index + 1). \(reminder.title)\(overdue ? "  •  OVERDUE" : "")",
                    in: CGRect(x: margin, y: y, width: pageBounds.width - margin * 2, height: 24),
                    font: .systemFont(ofSize: 13.5, weight: .semibold),
                    color: overdue ? .systemRed : .label,
                    alignment: .left
                )
                y += 25

                drawText(
                    "Due: \(dateFormatter.string(from: reminder.dueDate))",
                    in: CGRect(x: margin + 18, y: y, width: pageBounds.width - margin * 2 - 18, height: 18),
                    font: .systemFont(ofSize: 10.5),
                    color: .secondaryLabel,
                    alignment: .left
                )
                y += 18

                if let deadline = reminder.deadlineDate {
                    drawText(
                        "Deadline: \(dateFormatter.string(from: deadline))",
                        in: CGRect(x: margin + 18, y: y, width: pageBounds.width - margin * 2 - 18, height: 18),
                        font: .systemFont(ofSize: 10.5),
                        color: .secondaryLabel,
                        alignment: .left
                    )
                    y += 18
                }

                drawText(
                    "Priority: \(reminder.priority.title)",
                    in: CGRect(x: margin + 18, y: y, width: pageBounds.width - margin * 2 - 18, height: 18),
                    font: .systemFont(ofSize: 10.5, weight: .medium),
                    color: .secondaryLabel,
                    alignment: .left
                )
                y += 19

                if !notes.isEmpty {
                    let height = textHeight(
                        notes,
                        width: pageBounds.width - margin * 2 - 28,
                        font: .systemFont(ofSize: 10.5)
                    )
                    drawText(
                        notes,
                        in: CGRect(x: margin + 18, y: y, width: pageBounds.width - margin * 2 - 28, height: height + 3),
                        font: .systemFont(ofSize: 10.5),
                        color: .label,
                        alignment: .left
                    )
                    y += height + 7
                }

                UIColor.separator.setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y + 4))
                path.addLine(to: CGPoint(x: pageBounds.width - margin, y: y + 4))
                path.lineWidth = 0.5
                path.stroke()
                y += 14
            }

            ensureSpace(34)
            drawText(
                "Generated and saved locally by Next Reminder",
                in: CGRect(x: margin, y: y, width: pageBounds.width - margin * 2, height: 22),
                font: .systemFont(ofSize: 9.5),
                color: .tertiaryLabel,
                alignment: .center
            )
        }
    }

    private static func validEmail(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = cleaned.firstIndex(of: "@"), cleaned[cleaned.index(after: at)...].contains(".") else {
            return false
        }
        return !cleaned.contains(" ") && cleaned.count <= 254
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
            context: nil
        )
    }

    private static func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.height)
    }
}

private struct PendingReportEmailAttachment: Encodable {
    let fileName: String
    let mimeType: String
    let base64: String
}

private struct PendingReportEmailPayload: Encodable {
    let recipients: [String]
    let subject: String
    let body: String
    let remoteConnectorID: String
    let senderLabel: String
    let attachments: [PendingReportEmailAttachment]
}

private struct PendingReportEmailResponse: Decodable {
    let message: String?
}

enum PendingReportEmailError: LocalizedError {
    case invalidRecipient
    case gmailNotConnected
    case schedulerNotConfigured
    case invalidEndpoint
    case unreadablePDF
    case attachmentTooLarge
    case invalidResponse
    case connectorExpired
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidRecipient:
            return "Set a valid preset recipient in Settings → Email Reminder Automations first."
        case .gmailNotConnected:
            return "Connect Gmail in Next Reminder before sending the PDF."
        case .schedulerNotConfigured:
            return "Configure the HTTPS scheduler in Automation Connections first."
        case .invalidEndpoint:
            return "The scheduler URL is invalid."
        case .unreadablePDF:
            return "The saved PDF could not be read. Generate a new report and try again."
        case .attachmentTooLarge:
            return "The PDF is larger than the 8 MB attachment limit."
        case .invalidResponse:
            return "The Gmail scheduler returned an invalid response."
        case .connectorExpired:
            return "The saved Gmail connector is unavailable. Reconnect Gmail and try again; the PDF remains saved locally."
        case .server(let message):
            return message
        }
    }
}

struct PendingReportEmailService {
    static func isValidEmail(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = cleaned.firstIndex(of: "@"), cleaned[cleaned.index(after: at)...].contains(".") else {
            return false
        }
        return !cleaned.contains(" ") && cleaned.count <= 254
    }

    func send(
        report: PendingReminderPDFReport,
        recipient: String,
        gmail: GmailConnectionRecord,
        endpoint: String,
        apiKey: String
    ) async throws -> String {
        let recipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(recipient) else { throw PendingReportEmailError.invalidRecipient }
        guard !gmail.connectorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PendingReportEmailError.gmailNotConnected
        }
        guard !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PendingReportEmailError.schedulerNotConfigured
        }

        let normalized = endpoint.hasSuffix("/") ? endpoint : endpoint + "/"
        guard let baseURL = URL(string: normalized),
              baseURL.scheme?.lowercased() == "https",
              let url = URL(string: "v1/file-shares", relativeTo: baseURL)?.absoluteURL else {
            throw PendingReportEmailError.invalidEndpoint
        }

        let data: Data
        do {
            data = try Data(contentsOf: report.url)
        } catch {
            throw PendingReportEmailError.unreadablePDF
        }
        guard !data.isEmpty else { throw PendingReportEmailError.unreadablePDF }
        guard data.count <= 8_000_000 else { throw PendingReportEmailError.attachmentTooLarge }

        let payload = PendingReportEmailPayload(
            recipients: [recipient],
            subject: "Pending Reminders Report — \(report.reminderCount)",
            body: "Please find attached the pending reminders report generated by Next Reminder on \(report.createdAt.formatted(date: .long, time: .shortened)).",
            remoteConnectorID: gmail.connectorID,
            senderLabel: gmail.emailAddress,
            attachments: [
                PendingReportEmailAttachment(
                    fileName: report.fileName,
                    mimeType: "application/pdf",
                    base64: data.base64EncodedString()
                )
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("NextReminder-iOS/1.3.29.39", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(payload)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PendingReportEmailError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(PendingReportEmailResponse.self, from: responseData).message)
                ?? "PDF email failed (\(http.statusCode))."
            let lowered = message.lowercased()
            if lowered.contains("gmail connector not found")
                || lowered.contains("reconnect gmail")
                || lowered.contains("reconnect the gmail account") {
                throw PendingReportEmailError.connectorExpired
            }
            throw PendingReportEmailError.server(message)
        }

        return (try? JSONDecoder().decode(PendingReportEmailResponse.self, from: responseData).message)
            ?? "PDF sent successfully."
    }
}

struct PendingReportsView: View {
    @EnvironmentObject private var reminderStore: ReminderStore
    @EnvironmentObject private var automationStore: AutomationStore
    @EnvironmentObject private var emailStore: EmailAutomationStore

    @State private var savedReports: [PendingReminderPDFReport] = []
    @State private var isLoading = true
    @State private var isGenerating = false
    @State private var sendingID: UUID?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var gmailRecord: GmailConnectionRecord? = GmailConnectionStore.shared.load()

    private var recipient: String {
        emailStore.settings.recipient.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pendingCount: Int {
        reminderStore.pendingReminders.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                connectionCard
                generateButton

                if let statusMessage {
                    statusCard(statusMessage)
                }

                savedReportsSection
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("Pending Reports")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reloadReports() }
        .onReceive(NotificationCenter.default.publisher(for: .nextEmailAutomationSettingsChanged)) { _ in
            gmailRecord = GmailConnectionStore.shared.load()
        }
        .alert("Pending Reports", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                    Image(systemName: "doc.text.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Pending Reminders PDF")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Manual generation & email")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.84))
                }
                Spacer()
            }

            HStack(spacing: 10) {
                metricChip("\(pendingCount) pending", icon: "clock.fill")
                metricChip("Max 3 saved", icon: "tray.full.fill")
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.nextOrange, Color.orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: PendingReportEmailService.isValidEmail(recipient) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(PendingReportEmailService.isValidEmail(recipient) ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preset email")
                        .font(.subheadline.weight(.semibold))
                    Text(PendingReportEmailService.isValidEmail(recipient) ? recipient : "Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            HStack(spacing: 10) {
                Image(systemName: gmailRecord == nil ? "envelope.badge.fill" : "checkmark.seal.fill")
                    .foregroundStyle(gmailRecord == nil ? Color.orange : Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gmailRecord == nil ? "Gmail not connected" : "Gmail connected")
                        .font(.subheadline.weight(.semibold))
                    Text(gmailRecord?.emailAddress ?? "Connect Gmail before using Send Email")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !PendingReportEmailService.isValidEmail(recipient) {
                NavigationLink {
                    EmailAutomationSettingsView()
                } label: {
                    Label("Set preset email", systemImage: "gearshape.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(14)
        .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var generateButton: some View {
        Button {
            generateReport()
        } label: {
            HStack(spacing: 12) {
                if isGenerating {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "doc.badge.plus")
                        .font(.title3.bold())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isGenerating ? "Generating PDF…" : "Generate Pending Report")
                        .font(.headline)
                    Text(pendingCount == 0 ? "No pending reminders" : "Create PDF from \(pendingCount) reminders")
                        .font(.caption2)
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(Color.nextOrange, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isGenerating || pendingCount == 0)
        .opacity((isGenerating || pendingCount == 0) ? 0.55 : 1)
    }

    @ViewBuilder
    private var savedReportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved Reports")
                    .font(.headline)
                Spacer()
                Text("\(savedReports.count)/3")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading reports…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            } else if savedReports.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No reports saved yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Generate a PDF above. Only the newest three reports are kept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            } else {
                ForEach(savedReports) { report in
                    reportRow(report)
                }
            }
        }
    }

    private func reportRow(_ report: PendingReminderPDFReport) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "doc.richtext.fill")
                    .font(.title3)
                    .foregroundStyle(.nextOrange)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(report.fileName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text("\(report.reminderCount) reminders • \(report.sizeText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if savedReports.first?.id == report.id {
                    Text("LATEST")
                        .font(.caption2.bold())
                        .foregroundStyle(.nextOrange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.nextOrange.opacity(0.12), in: Capsule())
                }
            }

            HStack(spacing: 10) {
                Button {
                    sendReport(report)
                } label: {
                    HStack(spacing: 7) {
                        if sendingID == report.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(sendingID == report.id ? "Sending…" : "Send Email")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.nextOrange.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(sendingID != nil)

                ShareLink(item: report.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func metricChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.16), in: Capsule())
    }

    private func statusCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.nextOrange)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor
    private func reloadReports() async {
        isLoading = true
        let reports = await Task.detached(priority: .utility) {
            PendingReminderPDFReportService.savedReports()
        }.value
        savedReports = reports
        gmailRecord = GmailConnectionStore.shared.load()
        isLoading = false
    }

    private func generateReport() {
        guard !isGenerating else { return }
        let snapshot = reminderStore.pendingReminders
        let destination = recipient
        isGenerating = true
        statusMessage = "Generating pending-reminders PDF…"

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let report = try PendingReminderPDFReportService.generate(
                    reminders: snapshot,
                    defaultRecipient: destination
                )
                let reports = PendingReminderPDFReportService.savedReports()
                DispatchQueue.main.async {
                    isGenerating = false
                    savedReports = reports
                    statusMessage = "PDF saved: \(report.fileName). Latest \(reports.count) of 3 retained."
                }
            } catch {
                DispatchQueue.main.async {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                    statusMessage = nil
                }
            }
        }
    }

    private func sendReport(_ report: PendingReminderPDFReport) {
        guard PendingReportEmailService.isValidEmail(recipient) else {
            errorMessage = PendingReportEmailError.invalidRecipient.localizedDescription
            return
        }
        guard let gmail = GmailConnectionStore.shared.load() else {
            errorMessage = PendingReportEmailError.gmailNotConnected.localizedDescription
            return
        }

        let endpoint = automationStore.cloudEndpoint
        let apiKey = automationStore.cloudAPIKey
        guard !endpoint.isEmpty, !apiKey.isEmpty else {
            errorMessage = PendingReportEmailError.schedulerNotConfigured.localizedDescription
            return
        }

        sendingID = report.id
        statusMessage = "Sending \(report.fileName) to \(recipient)…"
        let destination = recipient

        Task {
            defer { sendingID = nil }
            do {
                let message = try await PendingReportEmailService().send(
                    report: report,
                    recipient: destination,
                    gmail: gmail,
                    endpoint: endpoint,
                    apiKey: apiKey
                )
                statusMessage = "Sent successfully to \(destination). \(message)"
                gmailRecord = GmailConnectionStore.shared.load() ?? gmail
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Send failed. The PDF remains saved locally."
                gmailRecord = GmailConnectionStore.shared.load() ?? gmail
            }
        }
    }
}
