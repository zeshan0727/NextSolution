import UIKit

@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        impact.prepare()
        selection.prepare()
        notification.prepare()
    }

    func copied() {
        impact.impactOccurred()
        impact.prepare()
    }

    func generated() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    func deleted() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    func selectionChanged() {
        selection.selectionChanged()
        selection.prepare()
    }

    func openedLink() {
        impact.impactOccurred(intensity: 0.82)
        impact.prepare()
    }
}
