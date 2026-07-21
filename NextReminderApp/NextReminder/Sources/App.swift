import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        NotificationManager.shared.configureCategories()
        AutomationNotificationCenter.shared.install()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        if let raw = response.notification.request.content.userInfo["automationID"] as? String, let id = UUID(uuidString: raw) {
            AutomationActionCoordinator.shared.store(.init(automationID: id, kind: response.actionIdentifier == AutomationNotificationCenter.skipAction ? .skip : .open))
            return
        }
        guard let raw = response.notification.request.content.userInfo["reminderID"] as? String, let id = UUID(uuidString: raw) else { return }
        switch response.actionIdentifier {
        case NotificationManager.completeActionIdentifier:
            NotificationActionCoordinator.shared.store(.init(reminderID: id, kind: .complete, comment: (response as? UNTextInputNotificationResponse)?.userText ?? ""))
        case NotificationManager.snoozeActionIdentifier:
            NotificationActionCoordinator.shared.store(.init(reminderID: id, kind: .snooze, comment: ""))
        default: break
        }
    }
}

@main struct NextReminderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ReminderStore()
    @StateObject private var automationStore = AutomationStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("NextReminder.ThemeMode") private var themeModeRaw = AppThemeMode.system.rawValue
    private var themeMode: AppThemeMode { AppThemeMode(rawValue: themeModeRaw) ?? .system }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(automationStore)
                .preferredColorScheme(themeMode.colorScheme)
                .tint(.nextOrange)
                .onChange(of: scenePhase) { if $0 == .active { automationStore.refreshDueStatuses() } }
        }
    }
}
