// MARK: - Sources/Extensions/Color+Hex.swift
import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red, green, blue, alpha: UInt64
        switch cleaned.count {
        case 8:
            red = value >> 24
            green = (value >> 16) & 0xFF
            blue = (value >> 8) & 0xFF
            alpha = value & 0xFF
        default:
            red = value >> 16
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
            alpha = 0xFF
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

// MARK: - Sources/Theme/AppTheme.swift
import SwiftUI

enum ThemePreference: String, CaseIterable, Identifiable {
    static let storageKey = "kba.theme.preference"

    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum BrandColor {
    static let navy = Color(hex: "091B2D")
    static let blue = Color(hex: "0C6E9E")
    static let teal = Color(hex: "13A3A1")
    static let gold = Color(hex: "D8A83E")
    static let paleBlue = Color(hex: "EAF5FA")
}

// MARK: - Sources/Configuration/AppConfiguration.swift
import Foundation

enum AppConfiguration {
    static let appName = "KBA Client"
    static let version = "0.1.0"
    static let build = "1"

    // Keep true during customer testing. The final release must switch this off
    // only after authenticated backend submission and encrypted document upload work.
    static let isLocalTestMode = true
    static let websiteURL = URL(string: "https://kbaccountant.com/")!
}

// MARK: - Sources/Models/AppModels.swift
import Foundation

// MARK: - Customer profile

enum Jurisdiction: String, Codable, CaseIterable, Identifiable, Hashable {
    case unitedKingdom = "United Kingdom"
    case unitedStates = "United States"
    case unitedArabEmirates = "United Arab Emirates"
    case qatar = "Qatar"
    case crossBorder = "Cross-border"

    var id: String { rawValue }

    var flag: String {
        switch self {
        case .unitedKingdom: return "🇬🇧"
        case .unitedStates: return "🇺🇸"
        case .unitedArabEmirates: return "🇦🇪"
        case .qatar: return "🇶🇦"
        case .crossBorder: return "🌍"
        }
    }

    var shortName: String {
        switch self {
        case .unitedKingdom: return "UK"
        case .unitedStates: return "USA"
        case .unitedArabEmirates: return "UAE"
        case .qatar: return "Qatar"
        case .crossBorder: return "Global"
        }
    }
}

enum CustomerType: String, Codable, CaseIterable, Identifiable {
    case individual = "Individual"
    case smallBusiness = "Small business / SME"
    case charity = "Charity"
    case internationalBusiness = "International business"

    var id: String { rawValue }
}

struct UserProfile: Codable, Equatable {
    var fullName: String
    var email: String
    var phone: String
    var companyName: String
    var jurisdiction: Jurisdiction
    var customerType: CustomerType
}

// MARK: - Services

struct KBAService: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let summary: String
    let details: String
    let systemImage: String
    let jurisdictions: [Jurisdiction]
    let highlights: [String]
}

// MARK: - Requests

enum RequestStatus: String, Codable, CaseIterable, Identifiable {
    case submitted = "Submitted"
    case underReview = "Under review"
    case awaitingDocuments = "Awaiting documents"
    case inProgress = "In progress"
    case completed = "Completed"
    case cancelled = "Cancelled"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .submitted: return "paperplane.fill"
        case .underReview: return "doc.text.magnifyingglass"
        case .awaitingDocuments: return "folder.badge.questionmark"
        case .inProgress: return "clock.arrow.circlepath"
        case .completed: return "checkmark.seal.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
}

enum RequestPriority: String, Codable, CaseIterable, Identifiable {
    case normal = "Normal"
    case urgent = "Urgent"
    var id: String { rawValue }
}

enum ContactMethod: String, Codable, CaseIterable, Identifiable {
    case phone = "Phone call"
    case email = "Email"
    case whatsapp = "WhatsApp"
    case videoCall = "Video call"
    var id: String { rawValue }
}

struct StatusEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let status: RequestStatus
    let date: Date
    let note: String

    init(id: UUID = UUID(), status: RequestStatus, date: Date = Date(), note: String) {
        self.id = id
        self.status = status
        self.date = date
        self.note = note
    }
}

struct ClientRequest: Identifiable, Codable, Hashable {
    let id: UUID
    let reference: String
    let serviceID: String
    let serviceName: String
    let createdAt: Date
    let jurisdiction: Jurisdiction
    let companyName: String
    let details: String
    let priority: RequestPriority
    let preferredContact: ContactMethod
    var status: RequestStatus
    var timeline: [StatusEvent]
}

// MARK: - Consultations and documents

struct ConsultationRequest: Identifiable, Codable, Hashable {
    let id: UUID
    let requestedDate: Date
    let contactMethod: ContactMethod
    let topic: String
    let notes: String
    let createdAt: Date
}

enum DocumentCategory: String, Codable, CaseIterable, Identifiable {
    case identity = "Identity / KYC"
    case tax = "Tax"
    case payroll = "Payroll"
    case accounting = "Accounting"
    case companyFormation = "Company formation"
    case other = "Other"

    var id: String { rawValue }
}

struct ImportedDocument: Identifiable, Codable, Hashable {
    let id: UUID
    let displayName: String
    let localFileName: String
    let addedAt: Date
    let category: DocumentCategory
    let sizeBytes: Int64
}

struct OfficeContact: Identifiable, Hashable {
    let jurisdiction: Jurisdiction
    let phone: String
    let whatsappDigits: String
    let address: String

    var id: Jurisdiction { jurisdiction }
}
