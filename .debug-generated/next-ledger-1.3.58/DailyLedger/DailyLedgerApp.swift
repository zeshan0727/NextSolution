import SwiftUI

@main
struct DailyLedgerApp: App {
    @StateObject private var store = LedgerStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("DailyLedgerAppearance") private var appearance = AppAppearance.system.rawValue

    init() {
        BackupSyncService.shared.registerBackgroundTask()
        BudgetNotificationService.configure()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .tint(AppTheme.purple)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .task {
                    // One bounded pass only. No permanent AI polling loop.
                    await SMSOpenAIAutoRecoveryCoordinator.shared.processPending()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        store.reload()
                        Task {
                            await SMSOpenAIAutoRecoveryCoordinator.shared.processPending()
                        }
                    } else if phase == .background {
                        BackupSyncService.shared.handleDidEnterBackground(
                            ledger: LedgerDiskStore.shared.load()
                        )
                    }
                }
        }
    }
}
