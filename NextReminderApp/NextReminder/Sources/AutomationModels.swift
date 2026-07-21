import Foundation
import SwiftUI

enum AutomationPlatform: String, Codable, CaseIterable, Identifiable {
    case whatsapp, instagramPost, instagramStory, xPost
    var id: String { rawValue }
    var title: String { switch self { case .whatsapp: return "WhatsApp Message"; case .instagramPost: return "Instagram Post"; case .instagramStory: return "Instagram Story"; case .xPost: return "X Post" } }
    var shortTitle: String { switch self { case .whatsapp: return "WhatsApp"; case .instagramPost: return "Instagram"; case .instagramStory: return "IG Story"; case .xPost: return "X" } }
    var symbol: String { switch self { case .whatsapp: return "message.fill"; case .instagramPost: return "camera.fill"; case .instagramStory: return "circle.dashed.inset.filled"; case .xPost: return "text.bubble.fill" } }
    var color: Color { switch self { case .whatsapp: return Color(red: 0.08, green: 0.72, blue: 0.35); case .instagramPost, .instagramStory: return Color(red: 0.78, green: 0.18, blue: 0.56); case .xPost: return .primary } }
    var contentPrompt: String { switch self { case .whatsapp: return "Message"; case .instagramPost, .instagramStory: return "Caption"; case .xPost: return "Post text" } }
}

enum AutomationAccountPlatform: String, Codable, CaseIterable, Identifiable { case whatsapp, instagram, x; var id: String { rawValue } }

enum AutomationAccountType: String, Codable, CaseIterable, Identifiable {
    case whatsappBusiness, instagramBusiness, instagramCreator, xDeveloper
    var id: String { rawValue }
    var title: String { switch self { case .whatsappBusiness: return "WhatsApp Business Cloud"; case .instagramBusiness: return "Instagram Business"; case .instagramCreator: return "Instagram Creator"; case .xDeveloper: return "X Developer Account" } }
    var platform: AutomationAccountPlatform { switch self { case .whatsappBusiness: return .whatsapp; case .instagramBusiness, .instagramCreator: return .instagram; case .xDeveloper: return .x } }
    func supports(_ platform: AutomationPlatform) -> Bool {
        switch (self, platform) {
        case (.whatsappBusiness, .whatsapp), (.instagramBusiness, .instagramPost), (.instagramBusiness, .instagramStory), (.instagramCreator, .instagramPost), (.xDeveloper, .xPost): return true
        default: return false
        }
    }
}

enum AutomationDeliveryMode: String, Codable, CaseIterable, Identifiable {
    case automaticCloud, approval, assisted
    var id: String { rawValue }
    var title: String { switch self { case .automaticCloud: return "Automatic Cloud"; case .approval: return "Ask Before Publishing"; case .assisted: return "Assisted" } }
    var symbol: String { switch self { case .automaticCloud: return "cloud.fill"; case .approval: return "checkmark.shield.fill"; case .assisted: return "hand.tap.fill" } }
    var explanation: String { switch self { case .automaticCloud: return "The job is uploaded to your connected scheduler and runs at the selected time."; case .approval: return "You receive an alert and approve the content before it is published or sent."; case .assisted: return "The app opens the correct compose/share screen with your content prepared." } }
}

enum AutomationStatus: String, Codable, CaseIterable, Identifiable {
    case draft, needsSetup, scheduled, awaitingApproval, processing, sent, published, failed, paused, skipped
    var id: String { rawValue }
    var title: String { switch self { case .draft: return "Draft"; case .needsSetup: return "Setup Required"; case .scheduled: return "Scheduled"; case .awaitingApproval: return "Needs Approval"; case .processing: return "Processing"; case .sent: return "Sent"; case .published: return "Published"; case .failed: return "Failed"; case .paused: return "Paused"; case .skipped: return "Skipped" } }
    var symbol: String { switch self { case .draft: return "doc.fill"; case .needsSetup: return "wrench.and.screwdriver.fill"; case .scheduled: return "clock.badge.checkmark.fill"; case .awaitingApproval: return "checkmark.shield.fill"; case .processing: return "arrow.triangle.2.circlepath"; case .sent, .published: return "checkmark.circle.fill"; case .failed: return "exclamationmark.triangle.fill"; case .paused: return "pause.circle.fill"; case .skipped: return "forward.end.circle.fill" } }
    var color: Color { switch self { case .draft, .paused, .skipped: return .secondary; case .needsSetup, .awaitingApproval: return .orange; case .scheduled: return .blue; case .processing: return .purple; case .sent, .published: return .green; case .failed: return .red } }
    var isFinished: Bool { self == .sent || self == .published || self == .skipped }
}

enum AutomationRepeat: String, Codable, CaseIterable, Identifiable {
    case never, daily, weekly, monthly, yearly
    var id: String { rawValue }; var title: String { rawValue.capitalized }
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? { switch self { case .never: return nil; case .daily: return calendar.date(byAdding: .day, value: 1, to: date); case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date); case .monthly: return calendar.date(byAdding: .month, value: 1, to: date); case .yearly: return calendar.date(byAdding: .year, value: 1, to: date) } }
}

enum AutomationAlertOffset: Int, Codable, CaseIterable, Identifiable, Hashable {
    case atTime = 0, fiveMinutes = 300, fifteenMinutes = 900, thirtyMinutes = 1800, oneHour = 3600
    var id: Int { rawValue }; var seconds: TimeInterval { TimeInterval(rawValue) }
    var title: String { switch self { case .atTime: return "At time"; case .fiveMinutes: return "5 min"; case .fifteenMinutes: return "15 min"; case .thirtyMinutes: return "30 min"; case .oneHour: return "1 hour" } }
}

struct AutomationAccount: Identifiable, Codable, Hashable {
    var id: UUID; var displayName: String; var handleOrNumber: String; var remoteAccountID: String; var accountType: AutomationAccountType; var automaticPublishingEnabled: Bool; var createdAt: Date
    init(id: UUID = UUID(), displayName: String, handleOrNumber: String = "", remoteAccountID: String = "", accountType: AutomationAccountType, automaticPublishingEnabled: Bool = false, createdAt: Date = Date()) { self.id=id; self.displayName=displayName; self.handleOrNumber=handleOrNumber; self.remoteAccountID=remoteAccountID; self.accountType=accountType; self.automaticPublishingEnabled=automaticPublishingEnabled; self.createdAt=createdAt }
    var isReadyForAutomaticPublishing: Bool { automaticPublishingEnabled && !remoteAccountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct AutomationMediaAttachment: Identifiable, Codable, Hashable { var id: UUID = UUID(); var fileName: String; var mimeType: String = "image/jpeg"; var byteCount: Int }
struct AutomationHistoryEntry: Identifiable, Codable, Hashable { var id: UUID = UUID(); var date: Date; var status: AutomationStatus; var comment: String }

struct SocialAutomation: Identifiable, Codable, Hashable {
    var id: UUID; var title: String; var platform: AutomationPlatform; var deliveryMode: AutomationDeliveryMode; var status: AutomationStatus; var scheduledAt: Date; var timeZoneIdentifier: String; var repeatRule: AutomationRepeat; var alertOffsets: Set<AutomationAlertOffset>; var accountID: UUID?; var recipient: String; var contentText: String; var altText: String; var linkURL: String; var media: AutomationMediaAttachment?; var retryEnabled: Bool; var maxRetries: Int; var retryCount: Int; var remoteJobID: String?; var lastError: String?; var createdAt: Date; var updatedAt: Date; var completedAt: Date?; var history: [AutomationHistoryEntry]
    init(id: UUID = UUID(), title: String, platform: AutomationPlatform, deliveryMode: AutomationDeliveryMode = .approval, status: AutomationStatus = .scheduled, scheduledAt: Date, timeZoneIdentifier: String = TimeZone.current.identifier, repeatRule: AutomationRepeat = .never, alertOffsets: Set<AutomationAlertOffset> = [.atTime], accountID: UUID? = nil, recipient: String = "", contentText: String = "", altText: String = "", linkURL: String = "", media: AutomationMediaAttachment? = nil, retryEnabled: Bool = true, maxRetries: Int = 3, retryCount: Int = 0, remoteJobID: String? = nil, lastError: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), completedAt: Date? = nil, history: [AutomationHistoryEntry] = []) { self.id=id; self.title=title; self.platform=platform; self.deliveryMode=deliveryMode; self.status=status; self.scheduledAt=scheduledAt; self.timeZoneIdentifier=timeZoneIdentifier; self.repeatRule=repeatRule; self.alertOffsets=alertOffsets; self.accountID=accountID; self.recipient=recipient; self.contentText=contentText; self.altText=altText; self.linkURL=linkURL; self.media=media; self.retryEnabled=retryEnabled; self.maxRetries=maxRetries; self.retryCount=retryCount; self.remoteJobID=remoteJobID; self.lastError=lastError; self.createdAt=createdAt; self.updatedAt=updatedAt; self.completedAt=completedAt; self.history=history }
    var isDue: Bool { scheduledAt <= Date() && !status.isFinished && status != .paused }
}

struct AutomationDatabase: Codable { var automations: [SocialAutomation]; var accounts: [AutomationAccount] }
struct AutomationCloudConfiguration { var endpoint: String; var apiKey: String; var isConfigured: Bool { guard let url = URL(string: endpoint), url.scheme == "https" else { return false }; return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
