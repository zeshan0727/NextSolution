import AuthenticationServices
import Foundation
import MessageUI
import Security
import SwiftUI
import UIKit

// MARK: - Secure Storage

enum SecureStore {
    private static let service = "com.aspiregroup.maintenance"

    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
    }

    static func load(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Gmail Connector

enum GmailConnectionError: LocalizedError {
    case schedulerNotConfigured
    case invalidEndpoint
    case invalidResponse
    case missingAuthorizationURL
    case cancelled
    case callbackMissingConnection
    case server(String)

    var errorDescription: String? {
        switch self {
        case .schedulerNotConfigured: return "Enter the HTTPS scheduler URL and API key first."
        case .invalidEndpoint: return "The scheduler URL must be a valid HTTPS address."
        case .invalidResponse: return "The Gmail connection service returned an invalid response."
        case .missingAuthorizationURL: return "The scheduler did not return a Google authorization link."
        case .cancelled: return "Gmail connection was cancelled."
        case .callbackMissingConnection: return "Google authorization completed without connector details."
        case .server(let message): return message
        }
    }
}

struct GmailConnectionRecord: Codable, Equatable {
    var connectorID: String
    var emailAddress: String
    var connectedAt: Date
}

private struct GmailStartPayload: Encodable {
    var callbackScheme: String
    var appName: String
}

private struct GmailStartResponse: Decodable {
    var authorizationURL: String?
    var sessionID: String?
    var message: String?
}

private struct GmailStatusResponse: Decodable {
    var connected: Bool?
    var connectorID: String?
    var emailAddress: String?
    var message: String?
}

@MainActor
final class GmailOAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GmailOAuthClient()
    private var activeSession: ASWebAuthenticationSession?

    func connect(configuration: EmailConfiguration, apiKey: String) async throws -> GmailConnectionRecord {
        var request = try makeRequest(path: "v1/connectors/gmail/start", method: "POST", configuration: configuration, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GmailStartPayload(callbackScheme: "aspiremaintenance", appName: "Aspire Maintenance"))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let start = try JSONDecoder().decode(GmailStartResponse.self, from: data)
        guard let rawURL = start.authorizationURL, let url = URL(string: rawURL) else {
            throw GmailConnectionError.missingAuthorizationURL
        }

        let callback = try await authenticate(at: url)
        if let record = connection(from: callback) { return record }
        guard let sessionID = start.sessionID else { throw GmailConnectionError.callbackMissingConnection }
        return try await fetchStatus(sessionID: sessionID, configuration: configuration, apiKey: apiKey)
    }

    func disconnect(configuration: EmailConfiguration, apiKey: String) async throws {
        guard !configuration.connectorID.isEmpty else { return }
        let encoded = configuration.connectorID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? configuration.connectorID
        let request = try makeRequest(path: "v1/connectors/gmail/\(encoded)", method: "DELETE", configuration: configuration, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }

    private func authenticate(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "aspiremaintenance") { callbackURL, error in
                self.activeSession = nil
                if let authenticationError = error as? ASWebAuthenticationSessionError,
                   authenticationError.code == .canceledLogin {
                    continuation.resume(throwing: GmailConnectionError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GmailConnectionError.callbackMissingConnection)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            guard session.start() else {
                activeSession = nil
                continuation.resume(throwing: GmailConnectionError.invalidResponse)
                return
            }
        }
    }

    private func connection(from url: URL) -> GmailConnectionRecord? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let connectorID = values["connector_id"] ?? values["connectorID"]
        let email = values["email"] ?? values["email_address"]
        guard let connectorID, !connectorID.isEmpty, let email, !email.isEmpty else { return nil }
        return GmailConnectionRecord(connectorID: connectorID, emailAddress: email, connectedAt: Date())
    }

    private func fetchStatus(sessionID: String, configuration: EmailConfiguration, apiKey: String) async throws -> GmailConnectionRecord {
        let encoded = sessionID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sessionID
        let request = try makeRequest(path: "v1/connectors/gmail/status?session_id=\(encoded)", method: "GET", configuration: configuration, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let status = try JSONDecoder().decode(GmailStatusResponse.self, from: data)
        guard status.connected == true,
              let connectorID = status.connectorID,
              let emailAddress = status.emailAddress else {
            throw GmailConnectionError.server(status.message ?? "Gmail connection is not complete.")
        }
        return GmailConnectionRecord(connectorID: connectorID, emailAddress: emailAddress, connectedAt: Date())
    }

    private func makeRequest(path: String, method: String, configuration: EmailConfiguration, apiKey: String) throws -> URLRequest {
        let endpoint = configuration.schedulerEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, !key.isEmpty else { throw GmailConnectionError.schedulerNotConfigured }
        let normalized = endpoint.hasSuffix("/") ? endpoint : endpoint + "/"
        guard let baseURL = URL(string: normalized), baseURL.scheme?.lowercased() == "https",
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw GmailConnectionError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("AspireMaintenance-iOS/1.0.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GmailConnectionError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(GmailStartResponse.self, from: data).message)
                ?? "Gmail connection failed (\(http.statusCode))."
            throw GmailConnectionError.server(message)
        }
    }
}

struct DirectEmailAttachment {
    var fileName: String
    var mimeType: String
    var data: Data
}

private struct DirectEmailAttachmentPayload: Encodable {
    var fileName: String
    var mimeType: String
    var base64: String
}

private struct DirectEmailPayload: Encodable {
    var recipients: [String]
    var subject: String
    var body: String
    var remoteConnectorID: String
    var senderLabel: String
    var attachments: [DirectEmailAttachmentPayload]
}

private struct DirectEmailResponse: Decodable {
    var id: String?
    var message: String?
}

enum DirectEmailError: LocalizedError {
    case gmailNotReady
    case invalidRecipient
    case invalidEndpoint
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .gmailNotReady: return "Connect Gmail in Settings before sending directly."
        case .invalidRecipient: return "The customer email address is not valid."
        case .invalidEndpoint: return "The saved scheduler URL is invalid."
        case .invalidResponse: return "The email service returned an invalid response."
        case .server(let message): return message
        }
    }
}

struct DirectEmailService {
    func send(recipient: String, subject: String, body: String, attachments: [DirectEmailAttachment], configuration: EmailConfiguration, apiKey: String) async throws -> String {
        guard !configuration.connectorID.isEmpty,
              !configuration.connectedEmail.isEmpty,
              !configuration.schedulerEndpoint.isEmpty,
              !apiKey.isEmpty else { throw DirectEmailError.gmailNotReady }
        guard Self.isValidEmail(recipient) else { throw DirectEmailError.invalidRecipient }

        let normalized = configuration.schedulerEndpoint.hasSuffix("/") ? configuration.schedulerEndpoint : configuration.schedulerEndpoint + "/"
        guard let baseURL = URL(string: normalized), baseURL.scheme?.lowercased() == "https",
              let url = URL(string: "v1/file-shares", relativeTo: baseURL)?.absoluteURL else {
            throw DirectEmailError.invalidEndpoint
        }

        let payload = DirectEmailPayload(
            recipients: [recipient],
            subject: subject,
            body: body,
            remoteConnectorID: configuration.connectorID,
            senderLabel: configuration.connectedEmail,
            attachments: attachments.map {
                DirectEmailAttachmentPayload(fileName: $0.fileName, mimeType: $0.mimeType, base64: $0.data.base64EncodedString())
            }
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AspireMaintenance-iOS/1.0.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DirectEmailError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(DirectEmailResponse.self, from: data).message)
                ?? "Email sending failed (\(http.statusCode))."
            throw DirectEmailError.server(message)
        }
        return (try? JSONDecoder().decode(DirectEmailResponse.self, from: data).message) ?? "Invoice sent successfully."
    }

    static func isValidEmail(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = cleaned.firstIndex(of: "@"), cleaned[cleaned.index(after: at)...].contains(".") else { return false }
        return !cleaned.contains(" ") && cleaned.count <= 254
    }
}

// MARK: - Invoice PDF

struct InvoicePDFService {
    private let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private let green = UIColor(red: 0.10, green: 0.48, blue: 0.29, alpha: 1)
    private let gold = UIColor(red: 0.91, green: 0.63, blue: 0.15, alpha: 1)
    private let dark = UIColor(red: 0.12, green: 0.16, blue: 0.15, alpha: 1)

    func makePDF(invoice: Invoice, customer: Customer, company: CompanyProfile) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            let cg = context.cgContext
            drawBackground(in: cg)
            drawLogoAndHeader(company: company)
            drawInvoiceTitle(invoice: invoice)
            drawBillTo(customer: customer)
            drawInvoiceMeta(invoice: invoice)
            drawItems(invoice: invoice, company: company)
            drawPayment(company: company)
            drawTerms(invoice: invoice)
            drawFooter(company: company)
        }
    }

    private func drawBackground(in context: CGContext) {
        context.setFillColor(UIColor.white.cgColor)
        context.fill(page)
        context.setFillColor(green.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: page.width, height: 12))
        context.setFillColor(gold.withAlphaComponent(0.12).cgColor)
        context.fillEllipse(in: CGRect(x: -120, y: 650, width: 300, height: 300))
    }

    private func drawLogoAndHeader(company: CompanyProfile) {
        let logoRect = CGRect(x: 42, y: 38, width: 72, height: 72)
        let path = UIBezierPath(ovalIn: logoRect)
        green.setStroke()
        path.lineWidth = 5
        path.stroke()
        drawText("a", in: CGRect(x: 57, y: 39, width: 45, height: 55), font: .systemFont(ofSize: 49, weight: .bold), color: green, alignment: .center)
        let leaf = UIBezierPath()
        leaf.move(to: CGPoint(x: 78, y: 78))
        leaf.addCurve(to: CGPoint(x: 98, y: 59), controlPoint1: CGPoint(x: 79, y: 65), controlPoint2: CGPoint(x: 90, y: 56))
        leaf.addCurve(to: CGPoint(x: 78, y: 78), controlPoint1: CGPoint(x: 101, y: 70), controlPoint2: CGPoint(x: 92, y: 79))
        gold.setFill()
        leaf.fill()

        drawText(company.tradingName.uppercased(), in: CGRect(x: 130, y: 40, width: 290, height: 30), font: .systemFont(ofSize: 24, weight: .bold), color: green)
        drawText(company.fullName, in: CGRect(x: 130, y: 70, width: 315, height: 38), font: .systemFont(ofSize: 11, weight: .medium), color: dark)
        let contact = [company.address, company.phone, company.email, company.website].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "  •  ")
        drawText(contact, in: CGRect(x: 42, y: 118, width: 510, height: 28), font: .systemFont(ofSize: 8.5), color: .darkGray)
        green.setFill()
        UIRectFill(CGRect(x: 42, y: 150, width: 510, height: 1.5))
    }

    private func drawInvoiceTitle(invoice: Invoice) {
        drawText("INVOICE", in: CGRect(x: 375, y: 32, width: 177, height: 55), font: .systemFont(ofSize: 35, weight: .heavy), color: dark, alignment: .right)
        drawText(invoice.number, in: CGRect(x: 375, y: 88, width: 177, height: 18), font: .monospacedSystemFont(ofSize: 11, weight: .semibold), color: green, alignment: .right)
    }

    private func drawBillTo(customer: Customer) {
        drawText("BILL TO", in: CGRect(x: 42, y: 172, width: 210, height: 20), font: .systemFont(ofSize: 13, weight: .bold), color: green)
        drawText(customer.name, in: CGRect(x: 42, y: 195, width: 270, height: 24), font: .systemFont(ofSize: 14, weight: .bold), color: dark)
        let details = [customer.address, customer.phone, customer.email].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
        drawText(details, in: CGRect(x: 42, y: 220, width: 270, height: 62), font: .systemFont(ofSize: 10), color: .darkGray)
    }

    private func drawInvoiceMeta(invoice: Invoice) {
        let labels = "ISSUE DATE\nDUE DATE\nSERVICE MONTH"
        let values = "\(DateFormatter.shortDate.string(from: invoice.issueDate))\n\(DateFormatter.shortDate.string(from: invoice.dueDate))\n\(DateFormatter.monthAndYear.string(from: invoice.serviceMonth))"
        drawText(labels, in: CGRect(x: 344, y: 176, width: 95, height: 76), font: .systemFont(ofSize: 10, weight: .bold), color: dark)
        drawText(values, in: CGRect(x: 440, y: 176, width: 112, height: 76), font: .systemFont(ofSize: 10), color: dark, alignment: .right)
    }

    private func drawItems(invoice: Invoice, company: CompanyProfile) {
        let top: CGFloat = 300
        green.setFill()
        UIRectFill(CGRect(x: 42, y: top, width: 510, height: 30))
        drawText("DESCRIPTION", in: CGRect(x: 52, y: top + 7, width: 280, height: 16), font: .systemFont(ofSize: 10, weight: .bold), color: .white)
        drawText("QTY", in: CGRect(x: 345, y: top + 7, width: 45, height: 16), font: .systemFont(ofSize: 10, weight: .bold), color: .white, alignment: .center)
        drawText("PRICE", in: CGRect(x: 397, y: top + 7, width: 65, height: 16), font: .systemFont(ofSize: 10, weight: .bold), color: .white, alignment: .right)
        drawText("AMOUNT", in: CGRect(x: 472, y: top + 7, width: 70, height: 16), font: .systemFont(ofSize: 10, weight: .bold), color: .white, alignment: .right)

        var y = top + 30
        for item in invoice.lineItems.prefix(8) {
            UIColor(white: 0.96, alpha: 1).setFill()
            UIRectFill(CGRect(x: 42, y: y, width: 510, height: 48))
            drawText(item.description, in: CGRect(x: 52, y: y + 10, width: 280, height: 30), font: .systemFont(ofSize: 10, weight: .medium), color: dark)
            drawText(String(format: "%.2f", item.quantity), in: CGRect(x: 345, y: y + 15, width: 45, height: 18), font: .systemFont(ofSize: 10), color: dark, alignment: .center)
            drawText(CurrencyFormatter.string(item.unitPrice, code: company.currencyCode), in: CGRect(x: 397, y: y + 15, width: 65, height: 18), font: .systemFont(ofSize: 9), color: dark, alignment: .right)
            drawText(CurrencyFormatter.string(item.amount, code: company.currencyCode), in: CGRect(x: 468, y: y + 15, width: 74, height: 18), font: .systemFont(ofSize: 9, weight: .semibold), color: dark, alignment: .right)
            y += 50
        }

        gold.setFill()
        UIRectFill(CGRect(x: 340, y: y + 8, width: 212, height: 42))
        drawText("TOTAL", in: CGRect(x: 352, y: y + 19, width: 70, height: 20), font: .systemFont(ofSize: 14, weight: .heavy), color: dark)
        drawText(CurrencyFormatter.string(invoice.total, code: company.currencyCode), in: CGRect(x: 425, y: y + 19, width: 115, height: 20), font: .systemFont(ofSize: 14, weight: .heavy), color: dark, alignment: .right)
    }

    private func drawPayment(company: CompanyProfile) {
        drawText("PAYMENT METHOD", in: CGRect(x: 42, y: 520, width: 220, height: 22), font: .systemFont(ofSize: 13, weight: .bold), color: green)
        var lines: [String] = []
        if !company.bankName.isEmpty { lines.append("Bank Name: \(company.bankName)") }
        if !company.accountHolderName.isEmpty { lines.append("Account Holder: \(company.accountHolderName)") }
        if !company.accountNumber.isEmpty { lines.append("Account Number: \(company.accountNumber)") }
        if !company.iban.isEmpty { lines.append("IBAN: \(company.iban)") }
        if !company.swiftCode.isEmpty { lines.append("SWIFT: \(company.swiftCode)") }
        lines.append("Currency: \(company.currencyCode)")
        if !company.taxRegistrationNumber.isEmpty { lines.append("TRN: \(company.taxRegistrationNumber)") }
        drawText(lines.joined(separator: "\n"), in: CGRect(x: 42, y: 548, width: 330, height: 115), font: .systemFont(ofSize: 10), color: dark)
    }

    private func drawTerms(invoice: Invoice) {
        drawText("TERMS OR NOTES", in: CGRect(x: 42, y: 690, width: 220, height: 22), font: .systemFont(ofSize: 13, weight: .bold), color: green)
        drawText(invoice.notes, in: CGRect(x: 42, y: 718, width: 360, height: 55), font: .systemFont(ofSize: 10), color: dark)
    }

    private func drawFooter(company: CompanyProfile) {
        green.setFill()
        UIRectFill(CGRect(x: 0, y: 816, width: page.width, height: 26))
        drawText("Built on Service  •  Landscaping  •  Gardening  •  General Maintenance", in: CGRect(x: 42, y: 822, width: 510, height: 14), font: .systemFont(ofSize: 8, weight: .medium), color: .white, alignment: .center)
    }

    private func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        text.draw(in: rect, withAttributes: attributes)
    }
}

// MARK: - Mail & Sharing

struct MailDraft: Identifiable {
    let id = UUID()
    var recipient: String
    var subject: String
    var body: String
    var attachmentData: Data
    var attachmentName: String
}

struct MailComposer: UIViewControllerRepresentable {
    var draft: MailDraft
    var onFinish: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([draft.recipient])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        controller.addAttachmentData(draft.attachmentData, mimeType: "application/pdf", fileName: draft.attachmentName)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
            onFinish(result)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum TemporaryFileService {
    static func write(data: Data, fileName: String) throws -> URL {
        let cleaned = fileName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(cleaned)
        try data.write(to: url, options: .atomic)
        return url
    }
}
