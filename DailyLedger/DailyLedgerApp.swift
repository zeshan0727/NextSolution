import SwiftUI

@main
struct DailyLedgerApp: App {
    @StateObject private var store = LedgerStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("DailyLedgerAppearance") private var appearance = AppAppearance.system.rawValue

    init() {
        BackupSyncService.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .tint(AppTheme.purple)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        store.reload()
                    } else if phase == .background {
                        BackupSyncService.shared.handleDidEnterBackground(
                            ledger: LedgerDiskStore.shared.load()
                        )
                    }
                }
        }
    }
}
