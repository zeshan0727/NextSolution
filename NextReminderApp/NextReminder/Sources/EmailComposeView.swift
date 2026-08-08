import MessageUI
import SwiftUI
import UIKit

struct EmailComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reminder: ReminderItem
    let settings: EmailAutomationSettings

    var body: some View {
        if MFMailComposeViewController.canSendMail() {
            MailComposeController(
                recipient: settings.recipient,
                subject: EmailTemplateRenderer.subject(for: reminder, settings: settings),
                body: EmailTemplateRenderer.body(for: reminder, settings: settings)
            )
        } else {
            VStack(spacing: 18) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.nextOrange)
                Text("Apple Mail Is Not Configured")
                    .font(.title3.bold())
                Text("Configure a mail account in iOS Settings, or open the prepared message in another installed mail app.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Open Prepared Email") { openMailURL() }
                    .buttonStyle(OrangeActionButtonStyle())
                Button("Close") { dismiss() }
            }
            .padding(24)
            .background(Color.nextBackground.ignoresSafeArea())
        }
    }

    private func openMailURL() {
        let subject = EmailTemplateRenderer.subject(for: reminder, settings: settings)
        let body = EmailTemplateRenderer.body(for: reminder, settings: settings)
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = settings.recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
        dismiss()
    }
}

private struct MailComposeController: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MFMailComposeViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
        }
    }
}
