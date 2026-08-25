//
// NextDroid native UTM application entry point.
// UTM is licensed under Apache License 2.0.
//

import SwiftUI
import AppIntents
import Foundation
import Combine
import CryptoKit
import UIKit

struct UTMApp: App {
    #if WITH_REMOTE
    private let data: UTMRemoteData
    #else
    private let data: UTMData
    #endif

    init() {
        #if WITH_REMOTE
        let data = UTMRemoteData()
        #else
        let data = UTMData()
        #endif
        self.data = data
        if #available(iOS 16, *) {
            AppDependencyManager.shared.add(dependency: data)
        }
    }

    var body: some Scene {
        WindowGroup {
            #if WITH_REMOTE
            UTMSingleWindowView(data: data)
            #else
            NextDroidRootView(data: data)
            #endif
        }
        .commands {
            VMCommands()
        }
    }
}
