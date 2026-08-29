from pathlib import Path

source_path = Path("NextSolutionLicenseAdmin/Sources/NextSolutionLicenseAdminApp.swift")
text = source_path.read_text()

# 1.0.6: normalize NextLock/NS Lock aliases and add direct PayPal transaction sync.
product_anchor = '''    static let all: [ProductConfig] = [.nextLock, .moduleGlass]
}
'''
product_replacement = '''    static let all: [ProductConfig] = [.nextLock, .moduleGlass]

    static func resolve(name: String = "", packageID: String = "") -> ProductConfig {
        let normalized = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        let package = packageID.lowercased()

        if ["nextlock", "nslock", "lockglyphtime"].contains(normalized)
            || ["com.nextsolution.lockglyphtime", "com.nextsolution.nextlock"].contains(package) {
            return .nextLock
        }
        if ["moduleglass", "moduleglasscc", "ccmodulebackgrounds"].contains(normalized)
            || package == moduleGlass.packageID.lowercased() {
            return .moduleGlass
        }
        return all.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.packageID.caseInsensitiveCompare(packageID) == .orderedSame
        }) ?? .nextLock
    }
}
'''
if product_anchor not in text:
    raise SystemExit("ProductConfig 1.0.5 anchor not found")
text = text.replace(product_anchor, product_replacement, 1)

# Protected PayPal credentials + REST Transaction Search models/client.
api_anchor = '''struct GitHubLicenseAPI {
'''
paypal_support = r'''struct PayPalCredentials: Codable {
    var clientID: String
    var clientSecret: String
}

struct PayPalCredentialStore {
    private static let directory = "NSAdmin"
    private static let file = "paypal-credentials.json"

    private static var url: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(directory, isDirectory: true).appendingPathComponent(file)
    }

    static func load() -> PayPalCredentials {
        guard let url,
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(PayPalCredentials.self, from: data) else {
            return PayPalCredentials(clientID: "", clientSecret: "")
        }
        return value
    }

    static func save(clientID: String, clientSecret: String) throws {
        guard let url else {
            throw NSError(domain: "NSAdmin.PayPal", code: 1, userInfo: [NSLocalizedDescriptionKey: "Application Support directory is unavailable."])
        }
        let directoryURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let credentials = PayPalCredentials(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let data = try JSONEncoder().encode(credentials)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
            .posixPermissions: 0o600
        ], ofItemAtPath: url.path)
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

struct PayPalAccessTokenResponse: Decodable {
    let accessToken: String
}

struct PayPalSearchResponse: Decodable {
    let transactionDetails: [PayPalTransactionDetail]?
}

struct PayPalTransactionDetail: Decodable {
    let transactionInfo: PayPalTransactionInfo
    let cartInfo: PayPalCartInfo?
}

struct PayPalTransactionInfo: Decodable {
    let transactionId: String
    let transactionStatus: String?
    let customField: String?
    let transactionSubject: String?
    let transactionNote: String?
}

struct PayPalCartInfo: Decodable {
    let itemDetails: [PayPalItemDetail]?
}

struct PayPalItemDetail: Decodable {
    let itemName: String?
}

struct PayPalRequestCandidate: Hashable {
    let transactionID: String
    let deviceID: String
    let deviceModel: String
    let iosVersion: String
}

enum PayPalSyncError: LocalizedError {
    case missingCredentials
    case invalidResponse
    case api(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Add your live PayPal Client ID and Secret in Settings first."
        case .invalidResponse:
            return "PayPal returned an invalid response."
        case .api(let code, let message):
            return "PayPal error \(code): \(message)"
        }
    }
}

struct PayPalTransactionAPI {
    private let baseURL = "https://api-m.paypal.com"

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func accessToken(credentials: PayPalCredentials) async throws -> String {
        let clientID = credentials.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = credentials.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, !secret.isEmpty else { throw PayPalSyncError.missingCredentials }
        guard let url = URL(string: "\(baseURL)/v1/oauth2/token") else { throw PayPalSyncError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let raw = "\(clientID):\(secret)"
        let encoded = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("grant_type=client_credentials".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PayPalSyncError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw PayPalSyncError.api(http.statusCode, String((String(data: data, encoding: .utf8) ?? "Unknown response").prefix(500)))
        }
        guard let token = try? decoder().decode(PayPalAccessTokenResponse.self, from: data).accessToken, !token.isEmpty else {
            throw PayPalSyncError.invalidResponse
        }
        return token
    }

    func fetchNextLockRequests(credentials: PayPalCredentials) async throws -> [PayPalRequestCandidate] {
        let token = try await accessToken(credentials: credentials)
        let end = Date()
        let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -30, to: end) ?? end.addingTimeInterval(-30 * 86400)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "\(baseURL)/v1/reporting/transactions")
        components?.queryItems = [
            URLQueryItem(name: "start_date", value: formatter.string(from: start)),
            URLQueryItem(name: "end_date", value: formatter.string(from: end)),
            URLQueryItem(name: "transaction_status", value: "S"),
            URLQueryItem(name: "fields", value: "all"),
            URLQueryItem(name: "page_size", value: "500"),
            URLQueryItem(name: "page", value: "1")
        ]
        guard let url = components?.url else { throw PayPalSyncError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("true", forHTTPHeaderField: "PayPal-Enforce-ISO8601-Format")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PayPalSyncError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw PayPalSyncError.api(http.statusCode, String((String(data: data, encoding: .utf8) ?? "Unknown response").prefix(500)))
        }
        guard let search = try? decoder().decode(PayPalSearchResponse.self, from: data) else {
            throw PayPalSyncError.invalidResponse
        }

        var candidates: [PayPalRequestCandidate] = []
        var seen = Set<String>()
        let devicePattern = #"NS-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}"#

        for detail in search.transactionDetails ?? [] {
            let info = detail.transactionInfo
            guard info.transactionStatus == nil || info.transactionStatus == "S" else { continue }

            let custom = info.customField ?? ""
            let itemNames = (detail.cartInfo?.itemDetails ?? []).compactMap { $0.itemName }
            let haystack = ([custom, info.transactionSubject ?? "", info.transactionNote ?? ""] + itemNames)
                .joined(separator: " | ")
            let upper = haystack.uppercased()

            let customParts = custom.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            var device = ""
            var model = ""
            var ios = ""
            var looksLikeNextLock = upper.contains("NEXTLOCK") || upper.contains("NS LOCK") || upper.contains("NSLOCK")

            if customParts.count >= 2 {
                let marker = customParts[0].uppercased().replacingOccurrences(of: " ", with: "")
                if ["NEXTLOCK", "NSLOCK"].contains(marker) {
                    looksLikeNextLock = true
                    device = customParts[1].uppercased()
                    if customParts.count > 3 { model = customParts[3] }
                    if customParts.count > 4 { ios = customParts[4] }
                }
            }

            guard looksLikeNextLock else { continue }
            if !GitHubLicenseAPI.validDevice(device),
               let range = upper.range(of: devicePattern, options: .regularExpression) {
                device = String(upper[range])
            }
            guard GitHubLicenseAPI.validDevice(device), !seen.contains(info.transactionId) else { continue }
            seen.insert(info.transactionId)
            candidates.append(PayPalRequestCandidate(
                transactionID: info.transactionId,
                deviceID: device,
                deviceModel: model,
                iosVersion: ios
            ))
        }
        return candidates
    }
}

''' + api_anchor
if api_anchor not in text:
    raise SystemExit("GitHubLicenseAPI insertion anchor not found")
text = text.replace(api_anchor, paypal_support, 1)

props_anchor = '''    @Published var settingsStatus = ""

    private let api = GitHubLicenseAPI()
'''
props_replacement = '''    @Published var settingsStatus = ""
    @Published var paypalClientIDDraft = PayPalCredentialStore.load().clientID
    @Published var paypalClientSecretDraft = PayPalCredentialStore.load().clientSecret
    @Published var paypalSyncStatus = ""
    @Published var isSyncingRequests = false
    @Published var lastRequestSync: Date?

    private let api = GitHubLicenseAPI()
    private let paypalAPI = PayPalTransactionAPI()
'''
if props_anchor not in text:
    raise SystemExit("AppModel PayPal properties anchor not found")
text = text.replace(props_anchor, props_replacement, 1)

old_handle = '''        let device = normalizeDevice(values["device"] ?? "")
        let name = values["product"] ?? "NextLock"
        let package = values["package"] ?? ""
        let payment = values["payment"] ?? ""
        let deviceModel = values["model"] ?? ""
        let iosVersion = values["ios"] ?? ""
        let product = ProductConfig.all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.packageID == package }) ?? .nextLock
        addRequest(product: product, deviceID: device, payment: payment, deviceModel: deviceModel, iosVersion: iosVersion)
'''
new_handle = '''        let device = normalizeDevice(values["device"] ?? values["device_id"] ?? "")
        let name = values["product"] ?? "NextLock"
        let package = values["package"] ?? ""
        let payment = values["payment"] ?? values["transaction_id"] ?? ""
        let deviceModel = values["model"] ?? ""
        let iosVersion = values["ios"] ?? values["os"] ?? ""
        let product = ProductConfig.resolve(name: name, packageID: package)
        addRequest(product: product, deviceID: device, payment: payment, deviceModel: deviceModel, iosVersion: iosVersion)
'''
if old_handle not in text:
    raise SystemExit("Request URL alias anchor not found")
text = text.replace(old_handle, new_handle, 1)

old_clipboard_product = '''            let product = ProductConfig.all.first(where: { $0.name.caseInsensitiveCompare(values["product"] ?? "") == .orderedSame }) ?? .nextLock
            addRequest(
                product: product,
                deviceID: values["device"] ?? "",
                payment: values["payment"] ?? "",
                deviceModel: values["model"] ?? "",
                iosVersion: values["ios"] ?? ""
            )
'''
new_clipboard_product = '''            let product = ProductConfig.resolve(name: values["product"] ?? "", packageID: values["package"] ?? "")
            addRequest(
                product: product,
                deviceID: values["device"] ?? values["device_id"] ?? "",
                payment: values["payment"] ?? values["transaction_id"] ?? "",
                deviceModel: values["model"] ?? "",
                iosVersion: values["ios"] ?? values["os"] ?? ""
            )
'''
if old_clipboard_product not in text:
    raise SystemExit("Clipboard alias anchor not found")
text = text.replace(old_clipboard_product, new_clipboard_product, 1)

save_token_anchor = '''    func saveToken() {
'''
paypal_methods = r'''    func savePayPalCredentials() {
        do {
            try PayPalCredentialStore.save(clientID: paypalClientIDDraft, clientSecret: paypalClientSecretDraft)
            let saved = PayPalCredentialStore.load()
            paypalClientIDDraft = saved.clientID
            paypalClientSecretDraft = saved.clientSecret
            paypalSyncStatus = saved.clientID.isEmpty || saved.clientSecret.isEmpty
                ? "PayPal credentials are incomplete."
                : "PayPal credentials saved in Protected App Storage."
        } catch {
            paypalSyncStatus = "Could not save PayPal credentials: \(error.localizedDescription)"
        }
    }

    func clearPayPalCredentials() {
        PayPalCredentialStore.clear()
        paypalClientIDDraft = ""
        paypalClientSecretDraft = ""
        paypalSyncStatus = "PayPal credentials removed."
    }

    func syncPayPalRequests(silent: Bool = false) async {
        let credentials = PayPalCredentialStore.load()
        guard !credentials.clientID.isEmpty, !credentials.clientSecret.isEmpty else {
            if !silent { paypalSyncStatus = "Add your live PayPal Client ID and Secret in Settings first." }
            return
        }

        isSyncingRequests = true
        if !silent { paypalSyncStatus = "Checking completed PayPal payments…" }
        do {
            let candidates = try await paypalAPI.fetchNextLockRequests(credentials: credentials)
            var imported = 0
            for candidate in candidates {
                let alreadyKnown = requests.contains {
                    $0.paymentReference == candidate.transactionID
                        || ($0.product == ProductConfig.nextLock.name && $0.deviceID == normalizeDevice(candidate.deviceID))
                }
                if !alreadyKnown { imported += 1 }
                addRequest(
                    product: .nextLock,
                    deviceID: candidate.deviceID,
                    payment: candidate.transactionID,
                    deviceModel: candidate.deviceModel,
                    iosVersion: candidate.iosVersion
                )
            }
            lastRequestSync = Date()
            paypalSyncStatus = imported > 0
                ? "Imported \(imported) new paid NextLock request\(imported == 1 ? "" : "s")."
                : "PayPal synced. No new paid NextLock requests."
        } catch {
            if !silent { paypalSyncStatus = error.localizedDescription }
        }
        isSyncingRequests = false
    }

''' + save_token_anchor
if save_token_anchor not in text:
    raise SystemExit("saveToken insertion anchor not found")
text = text.replace(save_token_anchor, paypal_methods, 1)

root_anchor = '''        .tint(.indigo)
    }
}
'''
root_replacement = '''        .tint(.indigo)
        .task {
            await model.syncPayPalRequests(silent: true)
        }
    }
}
'''
if root_anchor not in text:
    raise SystemExit("RootView task anchor not found")
text = text.replace(root_anchor, root_replacement, 1)

text = text.replace(
    'Text("After a customer shares an activation-request link, open it on this iPhone and tap Open in License Admin.")',
    'Text("Pull to refresh PayPal for completed NextLock payments, or import an activation-request link from the clipboard.")',
    1
)

refresh_anchor = '''            .refreshable { }
'''
refresh_replacement = '''            .refreshable {
                await model.syncPayPalRequests()
            }
'''
if refresh_anchor not in text:
    raise SystemExit("Requests refresh anchor not found")
text = text.replace(refresh_anchor, refresh_replacement, 1)

toolbar_anchor = '''            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.importClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .accessibilityLabel("Import request from clipboard")
                }
            }
'''
toolbar_replacement = '''            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await model.syncPayPalRequests() }
                    } label: {
                        if model.isSyncingRequests {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isSyncingRequests)
                    .accessibilityLabel("Sync paid PayPal requests")

                    Button {
                        model.importClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .accessibilityLabel("Import request from clipboard")
                }
            }
'''
if toolbar_anchor not in text:
    raise SystemExit("Requests toolbar anchor not found")
text = text.replace(toolbar_anchor, toolbar_replacement, 1)

list_anchor = '''            List {
                if pending.isEmpty {
'''
list_replacement = '''            List {
                if !model.paypalSyncStatus.isEmpty || model.lastRequestSync != nil {
                    Section("PayPal Sync") {
                        if model.isSyncingRequests {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Checking payments…")
                            }
                        }
                        if !model.paypalSyncStatus.isEmpty {
                            Text(model.paypalSyncStatus)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let synced = model.lastRequestSync {
                            LabeledContent("Last Sync", value: synced.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                        }
                    }
                }

                if pending.isEmpty {
'''
if list_anchor not in text:
    raise SystemExit("Requests list anchor not found")
text = text.replace(list_anchor, list_replacement, 1)

request_handoff_anchor = '''                Section("Request Handoff") {
'''
paypal_settings = '''                Section("PayPal Request Sync") {
                    TextField("Live PayPal Client ID", text: $model.paypalClientIDDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Live PayPal Client Secret", text: $model.paypalClientSecretDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save PayPal Credentials") { model.savePayPalCredentials() }
                    Button("Sync Paid Requests Now") {
                        Task { await model.syncPayPalRequests() }
                    }
                    .disabled(model.isSyncingRequests)
                    Button("Remove PayPal Credentials", role: .destructive) { model.clearPayPalCredentials() }

                    Text("NS Admin uses PayPal Transaction Search to import successful NextLock payments from the last 30 days. The Client Secret stays in this app's protected private storage. PayPal can take up to about three hours to expose a new payment through Transaction Search.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !model.paypalSyncStatus.isEmpty {
                        Text(model.paypalSyncStatus)
                            .font(.footnote)
                    }
                }

''' + request_handoff_anchor
if request_handoff_anchor not in text:
    raise SystemExit("Settings request handoff anchor not found")
text = text.replace(request_handoff_anchor, paypal_settings, 1)

text = text.replace(
    'Text("Activation links use the private URL scheme nextsolutionlicense://request. Opening a request link adds the Device ID and tweak name to the Requests tab automatically.")',
    'Text("Paid NextLock requests can sync directly from PayPal after credentials are configured. Deep links remain supported as a fallback: nextsolutionlicense://request.")',
    1
)

text = text.replace("NSAdmin/1.0.5", "NSAdmin/1.0.6")
text = text.replace('LabeledContent("Version", value: "1.0.5")', 'LabeledContent("Version", value: "1.0.6")')
source_path.write_text(text)

project_path = Path("NextSolutionLicenseAdmin/project.yml")
project = project_path.read_text()
project = project.replace('MARKETING_VERSION: "1.0.5"', 'MARKETING_VERSION: "1.0.6"')
project = project.replace('CURRENT_PROJECT_VERSION: "105"', 'CURRENT_PROJECT_VERSION: "106"')
project_path.write_text(project)

plist_path = Path("NextSolutionLicenseAdmin/Info.plist")
plist = plist_path.read_text()
plist = plist.replace('<key>CFBundleShortVersionString</key><string>1.0.5</string>', '<key>CFBundleShortVersionString</key><string>1.0.6</string>')
plist = plist.replace('<key>CFBundleVersion</key><string>105</string>', '<key>CFBundleVersion</key><string>106</string>')
plist_path.write_text(plist)

print("Patched NS Admin 1.0.6 with PayPal paid-request sync and NextLock aliases")
