from pathlib import Path
import re

source_path = Path('NextSolutionLicenseAdmin/Sources/NextSolutionLicenseAdminApp.swift')
text = source_path.read_text()

# Expand the registry schema while remaining compatible with existing registries
# that only contain the active SHA-256 token array.
old_registry = '''struct LicenseRegistry: Codable {
    var schema: Int
    var product: String
    var package: String
    var price: String
    var currency: String
    var updatedAt: String
    var active: [String]
}
'''
new_registry = '''struct LicenseDeviceRecord: Codable, Hashable {
    var token: String
    var maskedDeviceID: String
    var activatedAt: String
}

struct LicenseRegistry: Codable {
    var schema: Int
    var product: String
    var package: String
    var price: String
    var currency: String
    var updatedAt: String
    var active: [String]
    var devices: [LicenseDeviceRecord]?
}

struct KnownDevice: Codable, Hashable, Identifiable {
    var productID: String
    var product: String
    var packageID: String
    var deviceID: String
    var lastSeen: Date

    var id: String { "\\(productID)|\\(deviceID)" }
}

struct ActiveDeviceItem: Identifiable, Hashable {
    let id: String
    let productID: String
    let product: String
    let packageID: String
    let licenseToken: String
    let displayDeviceID: String
    let rawDeviceID: String?
    let activatedAt: String?
}
'''
if old_registry not in text:
    raise SystemExit('LicenseRegistry anchor not found')
text = text.replace(old_registry, new_registry, 1)

# Store privacy-safe display metadata with every new activation. The tweak still
# uses only the active hash array, so this is backward compatible.
old_active_update = '''            if shouldActivate { active.insert(license) } else { active.remove(license) }
            registry.active = Array(active).sorted()
            registry.updatedAt = ISO8601DateFormatter().string(from: Date())
'''
new_active_update = '''            if shouldActivate { active.insert(license) } else { active.remove(license) }
            registry.active = Array(active).sorted()

            var records = registry.devices ?? []
            if shouldActivate {
                let record = LicenseDeviceRecord(
                    token: license,
                    maskedDeviceID: Self.maskedDevice(device),
                    activatedAt: ISO8601DateFormatter().string(from: Date())
                )
                if let index = records.firstIndex(where: { $0.token.lowercased() == license }) {
                    records[index] = record
                } else {
                    records.append(record)
                }
            } else {
                records.removeAll { $0.token.lowercased() == license }
            }
            registry.devices = records.sorted { $0.maskedDeviceID < $1.maskedDeviceID }
            registry.updatedAt = ISO8601DateFormatter().string(from: Date())
'''
if old_active_update not in text:
    raise SystemExit('setActive update anchor not found')
text = text.replace(old_active_update, new_active_update, 1)

# Add token-direct revocation so legacy active entries can be revoked from the
# Active Devices screen even when the raw Device ID is not recoverable from its hash.
valid_anchor = '''    static func validDevice(_ value: String) -> Bool {
        value.range(of: #"^NS-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"#, options: .regularExpression) != nil
    }
'''
api_extension = '''    func revokeToken(_ licenseToken: String, product: ProductConfig, token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LicenseAdminError.missingToken }
        let license = licenseToken.lowercased()
        guard license.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw LicenseAdminError.invalidResponse
        }

        for attempt in 0..<2 {
            var (registry, sha) = try await loadRegistry(product: product, token: trimmed)
            registry.active = registry.active.map { $0.lowercased() }.filter { $0 != license }.sorted()
            var records = registry.devices ?? []
            records.removeAll { $0.token.lowercased() == license }
            registry.devices = records
            registry.updatedAt = ISO8601DateFormatter().string(from: Date())

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let registryData = try encoder.encode(registry)
            guard let url = URL(string: "https://api.github.com/repos/\\(owner)/\\(repo)/contents/\\(encodedPath(product.registryPath))") else {
                throw LicenseAdminError.invalidResponse
            }
            let payload: [String: Any] = [
                "message": "Revoke \\(product.name) device license",
                "content": registryData.base64EncodedString(),
                "sha": sha,
                "branch": branch
            ]
            let body = try JSONSerialization.data(withJSONObject: payload)
            let (responseData, response) = try await URLSession.shared.data(for: request(url: url, token: trimmed, method: "PUT", body: body))
            guard let http = response as? HTTPURLResponse else { throw LicenseAdminError.invalidResponse }
            if (200...299).contains(http.statusCode) { return }
            if http.statusCode == 409 && attempt == 0 { continue }
            let responseText = String(data: responseData, encoding: .utf8) ?? "Unknown response"
            throw LicenseAdminError.api(http.statusCode, String(responseText.prefix(600)))
        }
        throw LicenseAdminError.invalidResponse
    }

    static func maskedDevice(_ value: String) -> String {
        let parts = value.uppercased().split(separator: "-")
        guard parts.count == 5 else { return value.uppercased() }
        return "NS-\\(parts[1])-••••-••••-\\(parts[4])"
    }

''' + valid_anchor
if valid_anchor not in text:
    raise SystemExit('validDevice anchor not found')
text = text.replace(valid_anchor, api_extension, 1)

# Add a Devices tab.
old_tabs = '''enum AppTab: Hashable {
    case requests
    case activate
    case settings
}
'''
new_tabs = '''enum AppTab: Hashable {
    case requests
    case devices
    case activate
    case settings
}
'''
if old_tabs not in text:
    raise SystemExit('AppTab anchor not found')
text = text.replace(old_tabs, new_tabs, 1)

# Add active-device state and a local privacy-safe history of raw IDs known to
# this admin installation. This lets the UI show full IDs without publishing them.
props_anchor = '''    @Published var requests: [LicenseRequest] = []
    @Published var selectedTab: AppTab = .requests
'''
props_replacement = '''    @Published var requests: [LicenseRequest] = []
    @Published var activeDevices: [ActiveDeviceItem] = []
    @Published var devicesStatus = ""
    @Published var isRefreshingDevices = false
    @Published private(set) var knownDevices: [KnownDevice] = []
    @Published var selectedTab: AppTab = .requests
'''
if props_anchor not in text:
    raise SystemExit('AppModel properties anchor not found')
text = text.replace(props_anchor, props_replacement, 1)

key_anchor = '''    private let api = GitHubLicenseAPI()
    private let requestsKey = "NextSolutionLicenseAdmin.requests.v1"

    init() { loadRequests() }

    func normalizeDevice(_ value: String) -> String {
'''
key_replacement = '''    private let api = GitHubLicenseAPI()
    private let requestsKey = "NextSolutionLicenseAdmin.requests.v1"
    private let knownDevicesKey = "NextSolutionLicenseAdmin.knownDevices.v1"

    init() {
        loadRequests()
        loadKnownDevices()
        for request in requests {
            rememberDevice(request.deviceID, product: ProductConfig.all.first(where: { $0.id == request.product.lowercased() || $0.name == request.product || $0.packageID == request.packageID }) ?? .nextLock)
        }
    }

    func normalizeDevice(_ value: String) -> String {
'''
if key_anchor not in text:
    raise SystemExit('AppModel init anchor not found')
text = text.replace(key_anchor, key_replacement, 1)

# Remember every request ID locally.
request_guard = '''        guard GitHubLicenseAPI.validDevice(device) else {
            operationStatus = "Invalid Device ID."
            operationIsSuccess = false
            return
        }
        if let index = requests.firstIndex(where: { $0.product == product.name && $0.deviceID == device }) {
'''
request_guard_replacement = '''        guard GitHubLicenseAPI.validDevice(device) else {
            operationStatus = "Invalid Device ID."
            operationIsSuccess = false
            return
        }
        rememberDevice(device, product: product)
        if let index = requests.firstIndex(where: { $0.product == product.name && $0.deviceID == device }) {
'''
if request_guard not in text:
    raise SystemExit('addRequest guard anchor not found')
text = text.replace(request_guard, request_guard_replacement, 1)

# After activation/revocation, update the Devices screen immediately. The actual
# registry write has already succeeded at this point.
activation_success = '''            _ = try await api.setActive(activate, deviceID: device, product: selectedProduct, token: token)
            operationStatus = activate ? "Activated successfully." : "License revoked successfully."
            operationIsSuccess = true
            if let index = requests.firstIndex(where: { $0.deviceID == device && $0.product == selectedProduct.name }) {
'''
activation_success_replacement = '''            _ = try await api.setActive(activate, deviceID: device, product: selectedProduct, token: token)
            rememberDevice(device, product: selectedProduct)
            updateActiveSnapshot(deviceID: device, product: selectedProduct, activate: activate)
            operationStatus = activate ? "Activated successfully." : "License revoked successfully."
            operationIsSuccess = true
            if let index = requests.firstIndex(where: { $0.deviceID == device && $0.product == selectedProduct.name }) {
'''
if activation_success not in text:
    raise SystemExit('performActivation success anchor not found')
text = text.replace(activation_success, activation_success_replacement, 1)

# When manually checking a device, remember it and reconcile the Devices list.
check_success = '''            let active = try await api.isActive(deviceID: device, product: selectedProduct, token: token)
            operationStatus = active ? "This device is ACTIVE." : "This device is NOT active."
            operationIsSuccess = active
'''
check_success_replacement = '''            let active = try await api.isActive(deviceID: device, product: selectedProduct, token: token)
            rememberDevice(device, product: selectedProduct)
            updateActiveSnapshot(deviceID: device, product: selectedProduct, activate: active)
            operationStatus = active ? "This device is ACTIVE." : "This device is NOT active."
            operationIsSuccess = active
'''
if check_success not in text:
    raise SystemExit('checkActivation anchor not found')
text = text.replace(check_success, check_success_replacement, 1)

# Insert device-management methods before token settings methods.
save_token_anchor = '''    func saveToken() {
'''
management_methods = '''    func rememberDevice(_ value: String, product: ProductConfig) {
        let device = normalizeDevice(value)
        guard GitHubLicenseAPI.validDevice(device) else { return }
        if let index = knownDevices.firstIndex(where: { $0.productID == product.id && $0.deviceID == device }) {
            knownDevices[index].lastSeen = Date()
            knownDevices[index].product = product.name
            knownDevices[index].packageID = product.packageID
        } else {
            knownDevices.append(KnownDevice(
                productID: product.id,
                product: product.name,
                packageID: product.packageID,
                deviceID: device,
                lastSeen: Date()
            ))
        }
        saveKnownDevices()
    }

    private func updateActiveSnapshot(deviceID: String, product: ProductConfig, activate: Bool) {
        let device = normalizeDevice(deviceID)
        let license = api.licenseToken(deviceID: device, product: product).lowercased()
        if activate {
            let item = ActiveDeviceItem(
                id: "\\(product.id)|\\(license)",
                productID: product.id,
                product: product.name,
                packageID: product.packageID,
                licenseToken: license,
                displayDeviceID: device,
                rawDeviceID: device,
                activatedAt: ISO8601DateFormatter().string(from: Date())
            )
            activeDevices.removeAll { $0.id == item.id }
            activeDevices.insert(item, at: 0)
        } else {
            activeDevices.removeAll { $0.productID == product.id && $0.licenseToken == license }
        }
        devicesStatus = "\\(activeDevices.count) active device\\(activeDevices.count == 1 ? "" : "s")."
    }

    func refreshActiveDevices(showStatus: Bool = true) async {
        let token = LicenseTokenStore.load()
        guard !token.isEmpty else {
            devicesStatus = "Add your GitHub token in Settings first."
            if showStatus { selectedTab = .settings }
            return
        }
        isRefreshingDevices = true
        if showStatus { devicesStatus = "Refreshing active devices…" }
        do {
            var items: [ActiveDeviceItem] = []
            for product in ProductConfig.all {
                let (registry, _) = try await api.loadRegistry(product: product, token: token)
                let recordsByToken = Dictionary(uniqueKeysWithValues: (registry.devices ?? []).map { ($0.token.lowercased(), $0) })
                for license in Set(registry.active.map { $0.lowercased() }).sorted() {
                    let known = knownDevices.first { known in
                        known.productID == product.id && api.licenseToken(deviceID: known.deviceID, product: product).lowercased() == license
                    }
                    let record = recordsByToken[license]
                    let display: String
                    if let known {
                        display = known.deviceID
                    } else if let record, !record.maskedDeviceID.isEmpty {
                        display = record.maskedDeviceID
                    } else {
                        display = "Legacy device · \\(String(license.prefix(10)))…"
                    }
                    items.append(ActiveDeviceItem(
                        id: "\\(product.id)|\\(license)",
                        productID: product.id,
                        product: product.name,
                        packageID: product.packageID,
                        licenseToken: license,
                        displayDeviceID: display,
                        rawDeviceID: known?.deviceID,
                        activatedAt: record?.activatedAt
                    ))
                }
            }
            activeDevices = items.sorted {
                if $0.product == $1.product { return $0.displayDeviceID < $1.displayDeviceID }
                return $0.product < $1.product
            }
            devicesStatus = "\\(activeDevices.count) active device\\(activeDevices.count == 1 ? "" : "s")."
        } catch {
            devicesStatus = error.localizedDescription
        }
        isRefreshingDevices = false
    }

    func revokeActiveDevice(_ item: ActiveDeviceItem) async {
        let token = LicenseTokenStore.load()
        guard !token.isEmpty else {
            devicesStatus = "Add your GitHub token in Settings first."
            selectedTab = .settings
            return
        }
        guard let product = ProductConfig.all.first(where: { $0.id == item.productID }) else {
            devicesStatus = "Unknown tweak configuration."
            return
        }
        isWorking = true
        devicesStatus = "Revoking \\(item.displayDeviceID)…"
        do {
            try await api.revokeToken(item.licenseToken, product: product, token: token)
            activeDevices.removeAll { $0.id == item.id }
            if let raw = item.rawDeviceID,
               let index = requests.firstIndex(where: { $0.deviceID == raw && $0.product == product.name }) {
                requests[index].state = .revoked
                saveRequests()
            }
            devicesStatus = "Revoked successfully. \\(activeDevices.count) active device\\(activeDevices.count == 1 ? "" : "s") remaining."
        } catch {
            devicesStatus = error.localizedDescription
        }
        isWorking = false
    }

''' + save_token_anchor
if save_token_anchor not in text:
    raise SystemExit('saveToken insertion anchor not found')
text = text.replace(save_token_anchor, management_methods, 1)

# Persist known raw IDs only inside the admin app sandbox.
load_requests_anchor = '''    private func loadRequests() {
'''
known_storage = '''    private func loadKnownDevices() {
        guard let data = UserDefaults.standard.data(forKey: knownDevicesKey),
              let decoded = try? JSONDecoder().decode([KnownDevice].self, from: data) else { return }
        knownDevices = decoded
    }

    private func saveKnownDevices() {
        if let data = try? JSONEncoder().encode(knownDevices) {
            UserDefaults.standard.set(data, forKey: knownDevicesKey)
        }
    }

''' + load_requests_anchor
if load_requests_anchor not in text:
    raise SystemExit('loadRequests anchor not found')
text = text.replace(load_requests_anchor, known_storage, 1)

# Add the Devices tab to the root tab view.
root_anchor = '''            RequestsView()
                .tabItem { Label("Requests", systemImage: "tray.full") }
                .tag(AppTab.requests)
            ActivationView()
'''
root_replacement = '''            RequestsView()
                .tabItem { Label("Requests", systemImage: "tray.full") }
                .tag(AppTab.requests)
            ActiveDevicesView()
                .tabItem { Label("Devices", systemImage: "iphone.gen3") }
                .tag(AppTab.devices)
            ActivationView()
'''
if root_anchor not in text:
    raise SystemExit('RootView tab anchor not found')
text = text.replace(root_anchor, root_replacement, 1)

# Add the server-backed Active Devices UI before the existing activation screen.
activation_view_anchor = '''struct ActivationView: View {
'''
active_devices_view = '''struct ActiveDevicesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if model.activeDevices.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "iphone.slash")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text(model.isRefreshingDevices ? "Refreshing…" : "No active devices")
                                .font(.headline)
                            Text("Pull to refresh. Active licenses are read directly from the Next Solution registry.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    Section("Active · \\(model.activeDevices.count)") {
                        ForEach(model.activeDevices) { item in
                            ActiveDeviceRow(item: item)
                        }
                    }
                }

                if !model.devicesStatus.isEmpty {
                    Section("Status") {
                        HStack(spacing: 10) {
                            if model.isRefreshingDevices || model.isWorking { ProgressView() }
                            Text(model.devicesStatus)
                        }
                    }
                }

                Section {
                    Text("Full Device IDs stay only inside NS Admin. The public license registry stores SHA-256 activation tokens plus a masked display ID for new activations. Legacy licenses can still be revoked directly by token.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Active Devices")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refreshActiveDevices() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshingDevices || model.isWorking)
                    .accessibilityLabel("Refresh active devices")
                }
            }
            .refreshable { await model.refreshActiveDevices() }
            .task {
                if model.activeDevices.isEmpty {
                    await model.refreshActiveDevices(showStatus: false)
                }
            }
        }
    }
}

struct ActiveDeviceRow: View {
    @EnvironmentObject var model: AppModel
    let item: ActiveDeviceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(item.product).font(.headline)
                Spacer()
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }
            Text(item.displayDeviceID)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
            if item.rawDeviceID == nil {
                Text(item.displayDeviceID.hasPrefix("Legacy") ? "Legacy activation · raw Device ID was never stored" : "Device ID masked in public registry")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let activatedAt = item.activatedAt, !activatedAt.isEmpty {
                Label(activatedAt, systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let raw = item.rawDeviceID {
                    Button("Copy ID") { UIPasteboard.general.string = raw }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(role: .destructive) {
                    Task { await model.revokeActiveDevice(item) }
                } label: {
                    Label("Revoke", systemImage: "xmark.shield.fill")
                }
                .buttonStyle(.bordered)
                .disabled(model.isWorking)
            }
        }
        .padding(.vertical, 5)
    }
}

''' + activation_view_anchor
if activation_view_anchor not in text:
    raise SystemExit('ActivationView insertion anchor not found')
text = text.replace(activation_view_anchor, active_devices_view, 1)

# Version/user-agent bump after the 1.0.2 patch has run.
text = text.replace('NSAdmin/1.0.2', 'NSAdmin/1.0.3')
text = text.replace('LabeledContent("Version", value: "1.0.2")', 'LabeledContent("Version", value: "1.0.3")')

source_path.write_text(text)

# Build metadata is also patched at CI time so a 1.0.3 package is produced.
project_path = Path('NextSolutionLicenseAdmin/project.yml')
project = project_path.read_text()
project = project.replace('MARKETING_VERSION: "1.0.2"', 'MARKETING_VERSION: "1.0.3"')
project = project.replace('CURRENT_PROJECT_VERSION: "102"', 'CURRENT_PROJECT_VERSION: "103"')
project_path.write_text(project)

plist_path = Path('NextSolutionLicenseAdmin/Info.plist')
plist = plist_path.read_text()
plist = plist.replace('<key>CFBundleShortVersionString</key><string>1.0.2</string>', '<key>CFBundleShortVersionString</key><string>1.0.3</string>')
plist = plist.replace('<key>CFBundleVersion</key><string>102</string>', '<key>CFBundleVersion</key><string>103</string>')
plist_path.write_text(plist)

print('Patched NS Admin source for 1.0.3 active device management')
