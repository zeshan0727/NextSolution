import SwiftUI
import Foundation
import Security
import CryptoKit
import UIKit

struct ProductConfig: Identifiable, Hashable {
    let id: String
    let name: String
    let packageID: String
    let registryPath: String
    let price: String

    static let nextLock = ProductConfig(
        id: "nextlock",
        name: "NextLock",
        packageID: "com.nextsolution.lockglyphtime",
        registryPath: "licenses/nextlock.json",
        price: "$1.00"
    )

    static let all: [ProductConfig] = [.nextLock]
}

enum RequestState: String, Codable {
    case pending
    case activated
    case revoked
}

struct LicenseRequest: Identifiable, Codable, Hashable {
    var id: UUID
    var product: String
    var packageID: String
    var deviceID: String
    var paymentReference: String
    var receivedAt: Date
    var state: RequestState

    init(product: String, packageID: String, deviceID: String, paymentReference: String = "") {
        self.id = UUID()
        self.product = product
        self.packageID = packageID
        self.deviceID = deviceID
        self.paymentReference = paymentReference
        self.receivedAt = Date()
        self.state = .pending
    }
}

struct LicenseRegistry: Codable {
    var schema: Int
    var product: String
    var package: String
    var price: String
    var currency: String
    var updatedAt: String
    var active: [String]
}

struct GitHubContentResponse: Decodable {
    let content: String
    let sha: String
}

enum LicenseAdminError: LocalizedError {
    case missingToken
    case invalidDevice
    case invalidResponse
    case api(Int, String)
    case invalidRegistry

    var errorDescription: String? {
        switch self {
        case .missingToken: return "GitHub token is not configured."
        case .invalidDevice: return "Enter a valid Device ID in NS-XXXX-XXXX-XXXX-XXXX format."
        case .invalidResponse: return "GitHub returned an invalid response."
        case .api(let code, let message): return "GitHub error \(code): \(message)"
        case .invalidRegistry: return "The license registry could not be decoded."
        }
    }
}

struct LicenseTokenStore {
    private static let service = "com.nextsolution.licenseadmin.github"
    private static let account = "github-pat"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return delete() }
        guard let data = value.data(using: .utf8) else { return false }
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let update = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return true }
        if update != errSecItemNotFound { return false }
        var create = key
        create[kSecValueData as String] = data
        return SecItemAdd(create as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let result = SecItemDelete(query as CFDictionary)
        return result == errSecSuccess || result == errSecItemNotFound
    }
}

struct GitHubLicenseAPI {
    let owner = "zeshan0727"
    let repo = "NextSolution"
    let branch = "main"

    private func encodedPath(_ path: String) -> String {
        path.split(separator: "/").map { part in
            String(part).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(part)
        }.joined(separator: "/")
    }

    private func request(url: URL, token: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("NextSolutionLicenseAdmin/1.0.0", forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        return request
    }

    func loadRegistry(product: ProductConfig, token: String) async throws -> (LicenseRegistry, String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LicenseAdminError.missingToken }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(encodedPath(product.registryPath))?ref=\(branch)") else {
            throw LicenseAdminError.invalidResponse
        }
        let (data, response) = try await URLSession.shared.data(for: request(url: url, token: trimmed))
        guard let http = response as? HTTPURLResponse else { throw LicenseAdminError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown response"
            throw LicenseAdminError.api(http.statusCode, String(text.prefix(600)))
        }
        let content = try JSONDecoder().decode(GitHubContentResponse.self, from: data)
        let clean = content.content.replacingOccurrences(of: "\n", with: "")
        guard let registryData = Data(base64Encoded: clean),
              let registry = try? JSONDecoder().decode(LicenseRegistry.self, from: registryData) else {
            throw LicenseAdminError.invalidRegistry
        }
        return (registry, content.sha)
    }

    func licenseToken(deviceID: String, product: ProductConfig) -> String {
        let raw = "\(deviceID)|\(product.packageID)|nextsolution-license-v1"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func isActive(deviceID: String, product: ProductConfig, token: String) async throws -> Bool {
        let (registry, _) = try await loadRegistry(product: product, token: token)
        return registry.active.map { $0.lowercased() }.contains(licenseToken(deviceID: deviceID, product: product))
    }

    func setActive(_ shouldActivate: Bool, deviceID: String, product: ProductConfig, token: String) async throws -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LicenseAdminError.missingToken }
        let device = deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.validDevice(device) else { throw LicenseAdminError.invalidDevice }

        for attempt in 0..<2 {
            var (registry, sha) = try await loadRegistry(product: product, token: trimmed)
            let license = licenseToken(deviceID: device, product: product)
            var active = Set(registry.active.map { $0.lowercased() })
            if shouldActivate { active.insert(license) } else { active.remove(license) }
            registry.active = Array(active).sorted()
            registry.updatedAt = ISO8601DateFormatter().string(from: Date())

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let registryData = try encoder.encode(registry)
            guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(encodedPath(product.registryPath))") else {
                throw LicenseAdminError.invalidResponse
            }
            let payload: [String: Any] = [
                "message": shouldActivate ? "Activate \(product.name) device license" : "Revoke \(product.name) device license",
                "content": registryData.base64EncodedString(),
                "sha": sha,
                "branch": branch
            ]
            let body = try JSONSerialization.data(withJSONObject: payload)
            let (responseData, response) = try await URLSession.shared.data(for: request(url: url, token: trimmed, method: "PUT", body: body))
            guard let http = response as? HTTPURLResponse else { throw LicenseAdminError.invalidResponse }
            if (200...299).contains(http.statusCode) { return shouldActivate }
            if http.statusCode == 409 && attempt == 0 { continue }
            let text = String(data: responseData, encoding: .utf8) ?? "Unknown response"
            throw LicenseAdminError.api(http.statusCode, String(text.prefix(600)))
        }
        throw LicenseAdminError.invalidResponse
    }

    static func validDevice(_ value: String) -> Bool {
        value.range(of: #"^NS-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"#, options: .regularExpression) != nil
    }
}

enum AppTab: Hashable {
    case requests
    case activate
    case settings
}

@MainActor
final class AppModel: ObservableObject {
    @Published var requests: [LicenseRequest] = []
    @Published var selectedTab: AppTab = .requests
    @Published var selectedProduct: ProductConfig = .nextLock
    @Published var deviceID = ""
    @Published var paymentReference = ""
    @Published var operationStatus = ""
    @Published var operationIsSuccess = false
    @Published var isWorking = false
    @Published var tokenDraft = LicenseTokenStore.load()
    @Published var settingsStatus = ""

    private let api = GitHubLicenseAPI()
    private let requestsKey = "NextSolutionLicenseAdmin.requests.v1"

    init() { loadRequests() }

    func normalizeDevice(_ value: String) -> String {
        value.uppercased().replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func addRequest(product: ProductConfig, deviceID: String, payment: String = "") {
        let device = normalizeDevice(deviceID)
        guard GitHubLicenseAPI.validDevice(device) else {
            operationStatus = "Invalid Device ID."
            operationIsSuccess = false
            return
        }
        if let index = requests.firstIndex(where: { $0.product == product.name && $0.deviceID == device }) {
            requests[index].receivedAt = Date()
            if !payment.isEmpty { requests[index].paymentReference = payment }
            if requests[index].state != .activated { requests[index].state = .pending }
        } else {
            requests.insert(LicenseRequest(product: product.name, packageID: product.packageID, deviceID: device, paymentReference: payment), at: 0)
        }
        saveRequests()
        selectedTab = .requests
    }

    func handle(url: URL) {
        guard url.scheme?.lowercased() == "nextsolutionlicense",
              url.host?.lowercased() == "request",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let device = normalizeDevice(values["device"] ?? "")
        let name = values["product"] ?? "NextLock"
        let package = values["package"] ?? ""
        let payment = values["payment"] ?? ""
        let product = ProductConfig.all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.packageID == package }) ?? .nextLock
        addRequest(product: product, deviceID: device, payment: payment)
    }

    func importClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            operationStatus = "Clipboard is empty."
            operationIsSuccess = false
            return
        }
        if let url = URL(string: text), url.scheme?.lowercased() == "nextsolutionlicense" {
            handle(url: url)
            return
        }
        if let url = URL(string: text), url.host == "nextjailbreak.com", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let product = ProductConfig.all.first(where: { $0.name.caseInsensitiveCompare(values["product"] ?? "") == .orderedSame }) ?? .nextLock
            addRequest(product: product, deviceID: values["device"] ?? "", payment: values["payment"] ?? "")
            return
        }
        let pattern = #"NS-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}"#
        if let range = text.uppercased().range(of: pattern, options: .regularExpression) {
            addRequest(product: .nextLock, deviceID: String(text.uppercased()[range]))
        } else {
            operationStatus = "No valid Device ID found in clipboard."
            operationIsSuccess = false
        }
    }

    func prefill(_ request: LicenseRequest) {
        selectedProduct = ProductConfig.all.first(where: { $0.name == request.product || $0.packageID == request.packageID }) ?? .nextLock
        deviceID = request.deviceID
        paymentReference = request.paymentReference
        operationStatus = ""
        selectedTab = .activate
    }

    func delete(_ request: LicenseRequest) {
        requests.removeAll { $0.id == request.id }
        saveRequests()
    }

    func performActivation(activate: Bool) async {
        let device = normalizeDevice(deviceID)
        guard GitHubLicenseAPI.validDevice(device) else {
            operationStatus = "Invalid Device ID."
            operationIsSuccess = false
            return
        }
        let token = LicenseTokenStore.load()
        guard !token.isEmpty else {
            operationStatus = "Add your GitHub token in Settings first."
            operationIsSuccess = false
            selectedTab = .settings
            return
        }
        isWorking = true
        operationStatus = activate ? "Activating…" : "Revoking…"
        do {
            _ = try await api.setActive(activate, deviceID: device, product: selectedProduct, token: token)
            operationStatus = activate ? "Activated successfully." : "License revoked successfully."
            operationIsSuccess = true
            if let index = requests.firstIndex(where: { $0.deviceID == device && $0.product == selectedProduct.name }) {
                requests[index].state = activate ? .activated : .revoked
                if !paymentReference.isEmpty { requests[index].paymentReference = paymentReference }
                saveRequests()
            }
        } catch {
            operationStatus = error.localizedDescription
            operationIsSuccess = false
        }
        isWorking = false
    }

    func checkActivation() async {
        let device = normalizeDevice(deviceID)
        guard GitHubLicenseAPI.validDevice(device) else {
            operationStatus = "Invalid Device ID."
            operationIsSuccess = false
            return
        }
        let token = LicenseTokenStore.load()
        guard !token.isEmpty else {
            operationStatus = "Add your GitHub token in Settings first."
            operationIsSuccess = false
            selectedTab = .settings
            return
        }
        isWorking = true
        operationStatus = "Checking…"
        do {
            let active = try await api.isActive(deviceID: device, product: selectedProduct, token: token)
            operationStatus = active ? "This device is ACTIVE." : "This device is NOT active."
            operationIsSuccess = active
        } catch {
            operationStatus = error.localizedDescription
            operationIsSuccess = false
        }
        isWorking = false
    }

    func saveToken() {
        if LicenseTokenStore.save(tokenDraft) {
            tokenDraft = LicenseTokenStore.load()
            settingsStatus = tokenDraft.isEmpty ? "Token removed." : "Token saved securely in Keychain."
        } else {
            settingsStatus = "Could not save token to Keychain."
        }
    }

    func clearToken() {
        _ = LicenseTokenStore.delete()
        tokenDraft = ""
        settingsStatus = "Token removed."
    }

    func testConnection() async {
        let token = LicenseTokenStore.load()
        guard !token.isEmpty else { settingsStatus = "Save a GitHub token first."; return }
        isWorking = true
        do {
            let (registry, _) = try await api.loadRegistry(product: .nextLock, token: token)
            settingsStatus = "Connected. \(registry.active.count) active NextLock license(s)."
        } catch {
            settingsStatus = error.localizedDescription
        }
        isWorking = false
    }

    private func loadRequests() {
        guard let data = UserDefaults.standard.data(forKey: requestsKey),
              let decoded = try? JSONDecoder().decode([LicenseRequest].self, from: data) else { return }
        requests = decoded.sorted { $0.receivedAt > $1.receivedAt }
    }

    private func saveRequests() {
        if let data = try? JSONEncoder().encode(requests) {
            UserDefaults.standard.set(data, forKey: requestsKey)
        }
    }
}

@main
struct NextSolutionLicenseAdminApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { model.handle(url: $0) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            RequestsView()
                .tabItem { Label("Requests", systemImage: "tray.full") }
                .tag(AppTab.requests)
            ActivationView()
                .tabItem { Label("Activate", systemImage: "checkmark.shield") }
                .tag(AppTab.activate)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(.indigo)
    }
}

struct RequestsView: View {
    @EnvironmentObject var model: AppModel

    private var pending: [LicenseRequest] { model.requests.filter { $0.state == .pending } }
    private var completed: [LicenseRequest] { model.requests.filter { $0.state != .pending } }

    var body: some View {
        NavigationStack {
            List {
                if pending.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text("No pending requests")
                                .font(.headline)
                            Text("After a customer shares an activation-request link, open it on this iPhone and tap Open in License Admin.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    Section("Pending") {
                        ForEach(pending) { request in
                            RequestRow(request: request)
                        }
                    }
                }

                if !completed.isEmpty {
                    Section("History") {
                        ForEach(completed.prefix(20)) { request in
                            RequestRow(request: request)
                        }
                    }
                }
            }
            .navigationTitle("License Requests")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.importClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .accessibilityLabel("Import request from clipboard")
                }
            }
            .refreshable { }
        }
    }
}

struct RequestRow: View {
    @EnvironmentObject var model: AppModel
    let request: LicenseRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(request.product).font(.headline)
                Spacer()
                Text(request.state.rawValue.capitalized)
                    .font(.caption.bold())
                    .foregroundStyle(request.state == .activated ? .green : request.state == .revoked ? .red : .orange)
            }
            Text(request.deviceID)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
            if !request.paymentReference.isEmpty {
                Label(request.paymentReference, systemImage: "creditcard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(request.receivedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button("Copy ID") { UIPasteboard.general.string = request.deviceID }
                    .buttonStyle(.bordered)
                Button(request.state == .pending ? "Review" : "Open") { model.prefill(request) }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button(role: .destructive) { model.delete(request) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 5)
    }
}

struct ActivationView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("License") {
                    Picker("Tweak", selection: $model.selectedProduct) {
                        ForEach(ProductConfig.all) { product in
                            Text("\(product.name) · \(product.price)").tag(product)
                        }
                    }
                    TextField("NS-XXXX-XXXX-XXXX-XXXX", text: $model.deviceID)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("PayPal reference (optional)", text: $model.paymentReference)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        Task { await model.performActivation(activate: true) }
                    } label: {
                        Label("Activate Device", systemImage: "checkmark.shield.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.isWorking)

                    Button {
                        Task { await model.checkActivation() }
                    } label: {
                        Label("Check Activation", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.isWorking)

                    Button(role: .destructive) {
                        Task { await model.performActivation(activate: false) }
                    } label: {
                        Label("Revoke Device", systemImage: "xmark.shield.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.isWorking)
                }

                if !model.operationStatus.isEmpty {
                    Section("Result") {
                        HStack(alignment: .top, spacing: 10) {
                            if model.isWorking {
                                ProgressView()
                            } else {
                                Image(systemName: model.operationIsSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(model.operationIsSuccess ? .green : .orange)
                            }
                            Text(model.operationStatus)
                        }
                    }
                }

                Section {
                    Text("Activation writes only the SHA-256 license token to the public registry. The raw Device ID stays in this admin app and is never added to licenses/nextlock.json.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Activate License")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub Access") {
                    SecureField("Fine-grained GitHub token", text: $model.tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Token to Keychain") { model.saveToken() }
                    Button("Test Connection") { Task { await model.testConnection() } }
                        .disabled(model.isWorking)
                    Button("Remove Token", role: .destructive) { model.clearToken() }
                }

                Section("Required Permission") {
                    Text("Use a fine-grained GitHub personal access token restricted to zeshan0727/NextSolution with Repository contents: Read and write. The token is stored only in iOS Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !model.settingsStatus.isEmpty {
                    Section("Status") {
                        Text(model.settingsStatus)
                    }
                }

                Section("Request Handoff") {
                    Text("Activation links use the private URL scheme nextsolutionlicense://request. Opening a request link adds the Device ID and tweak name to the Requests tab automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("App", value: "NextSolution License Admin")
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Developer", value: "Next Jailbreak")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
