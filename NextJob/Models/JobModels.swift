import Foundation
import SwiftUI

enum JobStatus: String, CaseIterable, Codable, Identifiable {
    case notStarted
    case inProgress
    case waitingForDocuments
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .waitingForDocuments: return "Waiting for Documents"
        case .completed: return "Completed"
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted: return "circle"
        case .inProgress: return "clock.arrow.circlepath"
        case .waitingForDocuments: return "doc.badge.ellipsis"
        case .completed: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notStarted: return .secondary
        case .inProgress: return .blue
        case .waitingForDocuments: return .orange
        case .completed: return .green
        }
    }
}

enum PaymentStatus: String, CaseIterable, Codable, Identifiable {
    case pending
    case received

    var id: String { rawValue }
    var title: String { self == .pending ? "Payment Pending" : "Payment Received" }
    var shortTitle: String { self == .pending ? "Pending" : "Received" }
    var systemImage: String { self == .pending ? "clock.badge.exclamationmark" : "checkmark.seal.fill" }
    var tint: Color { self == .pending ? .orange : .green }
}

enum AttachmentKind: String, Codable, CaseIterable, Identifiable {
    case related
    case completedWork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .related: return "Related Files"
        case .completedWork: return "Completion Documents"
        }
    }

    var folderName: String {
        switch self {
        case .related: return "Related Files - Reference"
        case .completedWork: return "Completion Documents"
        }
    }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct JobAttachment: Identifiable, Codable, Equatable {
    var id: UUID
    var originalName: String
    var storedName: String
    var kind: AttachmentKind
    var addedAt: Date
    var byteCount: Int64
    var isFolder: Bool?
    var childCount: Int?

    init(
        id: UUID = UUID(),
        originalName: String,
        storedName: String,
        kind: AttachmentKind,
        addedAt: Date = Date(),
        byteCount: Int64,
        isFolder: Bool? = nil,
        childCount: Int? = nil
    ) {
        self.id = id
        self.originalName = originalName
        self.storedName = storedName
        self.kind = kind
        self.addedAt = addedAt
        self.byteCount = byteCount
        self.isFolder = isFolder
        self.childCount = childCount
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

struct JobEmailRecord: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case documentRequest
        case progress
        case completion
        case paymentFollowUp
        case custom
    }

    var id: UUID
    var kind: Kind
    var recipient: String
    var subject: String
    var sentAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        recipient: String,
        subject: String,
        sentAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.recipient = recipient
        self.subject = subject
        self.sentAt = sentAt
    }
}

struct JobRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var clientName: String
    var jobType: String
    var assignedDate: Date
    var dueDate: Date
    var completedDate: Date?
    var status: JobStatus
    var targetMinutes: Int
    var actualMinutes: Int?
    var price: Double
    var notes: String
    var requestedDocuments: String
    var completionNotes: String
    var attachments: [JobAttachment]
    var emailHistory: [JobEmailRecord]
    var createdAt: Date
    var updatedAt: Date
    var paymentStatus: PaymentStatus?
    var paymentReceivedDate: Date?
    var invoiceNumber: String?
    var invoiceIssuedDate: Date?
    var invoiceDueDate: Date?

    init(
        id: UUID = UUID(),
        title: String,
        clientName: String,
        jobType: String,
        assignedDate: Date,
        dueDate: Date,
        completedDate: Date? = nil,
        status: JobStatus = .notStarted,
        targetMinutes: Int = 60,
        actualMinutes: Int? = nil,
        price: Double = 0,
        notes: String = "",
        requestedDocuments: String = "",
        completionNotes: String = "",
        attachments: [JobAttachment] = [],
        emailHistory: [JobEmailRecord] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        paymentStatus: PaymentStatus? = nil,
        paymentReceivedDate: Date? = nil,
        invoiceNumber: String? = nil,
        invoiceIssuedDate: Date? = nil,
        invoiceDueDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.clientName = clientName
        self.jobType = jobType
        self.assignedDate = assignedDate
        self.dueDate = dueDate
        self.completedDate = completedDate
        self.status = status
        self.targetMinutes = targetMinutes
        self.actualMinutes = actualMinutes
        self.price = price
        self.notes = notes
        self.requestedDocuments = requestedDocuments
        self.completionNotes = completionNotes
        self.attachments = attachments
        self.emailHistory = emailHistory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.paymentStatus = paymentStatus
        self.paymentReceivedDate = paymentReceivedDate
        self.invoiceNumber = invoiceNumber
        self.invoiceIssuedDate = invoiceIssuedDate
        self.invoiceDueDate = invoiceDueDate
    }

    var isOverdue: Bool {
        status != .completed && dueDate < Calendar.current.startOfDay(for: Date())
    }

    var relatedFiles: [JobAttachment] { attachments.filter { $0.kind == .related } }
    var completedFiles: [JobAttachment] { attachments.filter { $0.kind == .completedWork } }
    var targetTimeText: String { Self.timeText(minutes: targetMinutes) }
    var actualTimeText: String {
        guard let actualMinutes else { return "Not recorded" }
        return Self.timeText(minutes: actualMinutes)
    }

    var effectivePaymentStatus: PaymentStatus? {
        paymentStatus ?? (status == .completed && price > 0 ? .pending : nil)
    }

    static func timeText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }
}

struct JobType: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct AppSettings: Codable, Equatable {
    var companyName: String
    var companyEmail: String
    var currency: String
    var theme: AppTheme
    var dueRemindersEnabled: Bool
    var jobTypes: [JobType]
    var invoiceFromName: String?
    var invoiceFromEmail: String?
    var invoiceFromAddress: String?
    var invoicePaymentInstructions: String?
    var invoiceTermsDays: Int?

    static let defaults = AppSettings(
        companyName: "KB Accountants",
        companyEmail: "",
        currency: "QAR",
        theme: .system,
        dueRemindersEnabled: true,
        jobTypes: [
            JobType(name: "Bookkeeping"),
            JobType(name: "Bank Reconciliation"),
            JobType(name: "VAT Return"),
            JobType(name: "Payroll"),
            JobType(name: "Accounts Preparation"),
            JobType(name: "Management Accounts"),
            JobType(name: "Year-End Accounts"),
            JobType(name: "Other")
        ],
        invoiceFromName: "Next Solution – Zeeshan Barvi",
        invoiceFromEmail: "",
        invoiceFromAddress: "Doha, Qatar",
        invoicePaymentInstructions: "Please arrange payment against this invoice and quote the invoice number.",
        invoiceTermsDays: 7
    )
}

struct AppDatabase: Codable {
    var jobs: [JobRecord]
    var settings: AppSettings
    static let empty = AppDatabase(jobs: [], settings: .defaults)
}

struct DashboardSummary {
    let total: Int
    let notStarted: Int
    let inProgress: Int
    let waiting: Int
    let completed: Int
    let overdue: Int
    let completedValue: Double
    let outstandingValue: Double
    let targetMinutes: Int
    let actualMinutes: Int
}
