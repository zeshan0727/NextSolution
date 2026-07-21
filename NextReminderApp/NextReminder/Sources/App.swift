import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

// MARK: - NextReminderApp
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        NotificationManager.shared.configureCategories()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let rawID = response.notification.request.content.userInfo["reminderID"] as? String,
              let reminderID = UUID(uuidString: rawID) else { return }

        switch response.actionIdentifier {
        case NotificationManager.completeActionIdentifier:
            let comment = (response as? UNTextInputNotificationResponse)?.userText ?? ""
            NotificationActionCoordinator.shared.store(
                PendingNotificationAction(reminderID: reminderID, kind: .complete, comment: comment)
            )
        case NotificationManager.snoozeActionIdentifier:
            NotificationActionCoordinator.shared.store(
                PendingNotificationAction(reminderID: reminderID, kind: .snooze, comment: "")
            )
        default:
            break
        }
    }
}

@main
struct NextReminderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ReminderStore()
    @AppStorage("NextReminder.ThemeMode") private var themeModeRaw = AppThemeMode.system.rawValue

    private var themeMode: AppThemeMode {
        AppThemeMode(rawValue: themeModeRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(themeMode.colorScheme)
                .tint(.nextOrange)
        }
    }
}
