import Foundation
import WebKit

@MainActor
enum BrowserDataManager {
    static func clearAll(completion: @escaping () -> Void = {}) {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {
                DispatchQueue.main.async { completion() }
            }
        }
    }
}
