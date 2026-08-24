import UIKit

@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        impact.prepare()
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
}
