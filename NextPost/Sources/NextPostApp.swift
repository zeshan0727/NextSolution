import SwiftUI

@main
struct NextPostApp: App {
    init() {
        AdsManager.shared.initializeIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .overlay(alignment: .topTrailing) {
                    AdTestDeviceButton()
                        .padding(.top, 8)
                        .padding(.trailing, 12)
                }
        }
    }
}
