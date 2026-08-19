import SwiftUI
import UIKit

struct AutomationStatusBadge: View {
    let status: AutomationStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption2.bold())
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(status.color.opacity(0.14), in: Capsule())
    }
}

struct AutomationModeBadge: View {
    let mode: AutomationDeliveryMode

    var body: some View {
        Label(mode.title, systemImage: mode.symbol)
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct AutomationMediaView: View {
    let url: URL?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.nextCard
                    Image(systemName: "photo.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct AutomationCard: View {
    let item: SocialAutomation
    let accountName: String?
    let mediaURL: URL?

    var body: some View {
        HStack(spacing: 13) {
            leadingIcon

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.scheduledAt.compactDateTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let accountName {
                    Text(accountName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                AutomationStatusBadge(status: item.status)
                AutomationModeBadge(mode: item.deliveryMode)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [item.platform.color.opacity(0.10), Color.nextCard.opacity(0.98)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(item.platform.color.opacity(0.20), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if item.media != nil {
            AutomationMediaView(url: mediaURL)
        } else {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(item.platform.color.opacity(0.14))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: item.platform.symbol)
                        .font(.title2.bold())
                        .foregroundStyle(item.platform.color)
                )
        }
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct IdentifiedAutomationID: Identifiable, Equatable {
    let id: UUID
}

enum AddFlow: String, Identifiable {
    case reminder
    case automation

    var id: String { rawValue }
}

enum AutomationListFilter: String, CaseIterable, Identifiable {
    case all
    case scheduled
    case attention
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .scheduled: return "Scheduled"
        case .attention: return "Attention"
        case .history: return "History"
        }
    }
}
