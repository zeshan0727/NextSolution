import SwiftUI

@main
struct DailyLedgerApp: App {
    @StateObject private var store = LedgerStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackupSyncService.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .tint(AppTheme.purple)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        store.reload()
                    } else if phase == .background {
                        BackupSyncService.shared.syncNow(ledger: LedgerDiskStore.shared.load())
                        BackupSyncService.shared.scheduleBackgroundRefresh()
                    }
                }
        }
    }
}
