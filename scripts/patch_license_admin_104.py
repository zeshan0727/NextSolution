from pathlib import Path

source_path = Path('NextSolutionLicenseAdmin/Sources/NextSolutionLicenseAdminApp.swift')
text = source_path.read_text()

# Device details captured from activation requests.
old_request_fields = '''    var paymentReference: String
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
'''
new_request_fields = '''    var paymentReference: String
    var receivedAt: Date
    var state: RequestState
    var deviceModel: String?
    var iosVersion: String?

    init(product: String, packageID: String, deviceID: String, paymentReference: String = "", deviceModel: String? = nil, iosVersion: String? = nil) {
        self.id = UUID()
        self.product = product
        self.packageID = packageID
        self.deviceID = deviceID
        self.paymentReference = paymentReference
        self.receivedAt = Date()
        self.state = .pending
        self.deviceModel = deviceModel
        self.iosVersion = iosVersion
    }
'''
if old_request_fields not in text:
    raise SystemExit('LicenseRequest fields anchor not found')
text = text.replace(old_request_fields, new_request_fields, 1)

old_record = '''struct LicenseDeviceRecord: Codable, Hashable {
    var token: String
    var maskedDeviceID: String
    var activatedAt: String
}
'''
new_record = '''struct LicenseDeviceRecord: Codable, Hashable {
    var token: String
    var maskedDeviceID: String
    var activatedAt: String
    var deviceModel: String?
    var iosVersion: String?
}
'''
if old_record not in text:
    raise SystemExit('LicenseDeviceRecord anchor not found')
text = text.replace(old_record, new_record, 1)

old_active_item = '''    let displayDeviceID: String
    let rawDeviceID: String?
    let activatedAt: String?
}
'''
new_active_item = '''    let displayDeviceID: String
    let rawDeviceID: String?
    let activatedAt: String?
    let deviceModel: String?
    let iosVersion: String?
}
'''
if old_active_item not in text:
    raise SystemExit('ActiveDeviceItem anchor not found')
text = text.replace(old_active_item, new_active_item, 1)

old_set_signature = '''    func setActive(_ shouldActivate: Bool, deviceID: String, product: ProductConfig, token: String) async throws -> Bool {'''
new_set_signature = '''    func setActive(_ shouldActivate: Bool, deviceID: String, product: ProductConfig, token: String, deviceModel: String? = nil, iosVersion: String? = nil) async throws -> Bool {'''
if old_set_signature not in text:
    raise SystemExit('setActive signature anchor not found')
text = text.replace(old_set_signature, new_set_signature, 1)

old_record_build = '''                let record = LicenseDeviceRecord(
                    token: license,
                    maskedDeviceID: Self.maskedDevice(device),
                    activatedAt: ISO8601DateFormatter().string(from: Date())
                )
'''
new_record_build = '''                let cleanModel = deviceModel?.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanIOS = iosVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
                let record = LicenseDeviceRecord(
                    token: license,
                    maskedDeviceID: Self.maskedDevice(device),
                    activatedAt: ISO8601DateFormatter().string(from: Date()),
                    deviceModel: (cleanModel?.isEmpty == false ? cleanModel : nil),
                    iosVersion: (cleanIOS?.isEmpty == false ? cleanIOS : nil)
                )
'''
if old_record_build not in text:
    raise SystemExit('license record build anchor not found')
text = text.replace(old_record_build, new_record_build, 1)

# Accept device model/iOS metadata in incoming requests.
old_add_signature = '''    func addRequest(product: ProductConfig, deviceID: String, payment: String = "") {'''
new_add_signature = '''    func addRequest(product: ProductConfig, deviceID: String, payment: String = "", deviceModel: String = "", iosVersion: String = "") {'''
if old_add_signature not in text:
    raise SystemExit('addRequest signature anchor not found')
text = text.replace(old_add_signature, new_add_signature, 1)

old_request_update = '''        if let index = requests.firstIndex(where: { $0.product == product.name && $0.deviceID == device }) {
            requests[index].receivedAt = Date()
            if !payment.isEmpty { requests[index].paymentReference = payment }
            if requests[index].state != .activated { requests[index].state = .pending }
        } else {
            requests.insert(LicenseRequest(product: product.name, packageID: product.packageID, deviceID: device, paymentReference: payment), at: 0)
        }
'''
new_request_update = '''        let cleanModel = deviceModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanIOS = iosVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = requests.firstIndex(where: { $0.product == product.name && $0.deviceID == device }) {
            requests[index].receivedAt = Date()
            if !payment.isEmpty { requests[index].paymentReference = payment }
            if !cleanModel.isEmpty { requests[index].deviceModel = cleanModel }
            if !cleanIOS.isEmpty { requests[index].iosVersion = cleanIOS }
            if requests[index].state != .activated { requests[index].state = .pending }
        } else {
            requests.insert(LicenseRequest(
                product: product.name,
                packageID: product.packageID,
                deviceID: device,
                paymentReference: payment,
                deviceModel: cleanModel.isEmpty ? nil : cleanModel,
                iosVersion: cleanIOS.isEmpty ? nil : cleanIOS
            ), at: 0)
        }
'''
if old_request_update not in text:
    raise SystemExit('addRequest update block anchor not found')
text = text.replace(old_request_update, new_request_update, 1)

old_handle = '''        let payment = values["payment"] ?? ""
        let product = ProductConfig.all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.packageID == package }) ?? .nextLock
        addRequest(product: product, deviceID: device, payment: payment)
'''
new_handle = '''        let payment = values["payment"] ?? ""
        let deviceModel = values["model"] ?? ""
        let iosVersion = values["ios"] ?? ""
        let product = ProductConfig.all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.packageID == package }) ?? .nextLock
        addRequest(product: product, deviceID: device, payment: payment, deviceModel: deviceModel, iosVersion: iosVersion)
'''
if old_handle not in text:
    raise SystemExit('request URL handler anchor not found')
text = text.replace(old_handle, new_handle, 1)

old_web_clipboard = '''            let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let product = ProductConfig.all.first(where: { $0.name.caseInsensitiveCompare(values["product"] ?? "") == .orderedSame }) ?? .nextLock
            addRequest(product: product, deviceID: values["device"] ?? "", payment: values["payment"] ?? "")
            return
'''
new_web_clipboard = '''            let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let product = ProductConfig.all.first(where: { $0.name.caseInsensitiveCompare(values["product"] ?? "") == .orderedSame }) ?? .nextLock
            addRequest(
                product: product,
                deviceID: values["device"] ?? "",
                payment: values["payment"] ?? "",
                deviceModel: values["model"] ?? "",
                iosVersion: values["ios"] ?? ""
            )
            return
'''
if old_web_clipboard not in text:
    raise SystemExit('clipboard request anchor not found')
text = text.replace(old_web_clipboard, new_web_clipboard, 1)

# Pass request metadata into the registry when activating.
old_activation_call = '''            _ = try await api.setActive(activate, deviceID: device, product: selectedProduct, token: token)
            rememberDevice(device, product: selectedProduct)
            updateActiveSnapshot(deviceID: device, product: selectedProduct, activate: activate)
'''
new_activation_call = '''            let requestDetails = requests.first(where: { $0.deviceID == device && $0.product == selectedProduct.name })
            _ = try await api.setActive(
                activate,
                deviceID: device,
                product: selectedProduct,
                token: token,
                deviceModel: requestDetails?.deviceModel,
                iosVersion: requestDetails?.iosVersion
            )
            rememberDevice(device, product: selectedProduct)
            updateActiveSnapshot(
                deviceID: device,
                product: selectedProduct,
                activate: activate,
                deviceModel: requestDetails?.deviceModel,
                iosVersion: requestDetails?.iosVersion
            )
'''
if old_activation_call not in text:
    raise SystemExit('performActivation API call anchor not found')
text = text.replace(old_activation_call, new_activation_call, 1)

old_snapshot_signature = '''    private func updateActiveSnapshot(deviceID: String, product: ProductConfig, activate: Bool) {'''
new_snapshot_signature = '''    private func updateActiveSnapshot(deviceID: String, product: ProductConfig, activate: Bool, deviceModel: String? = nil, iosVersion: String? = nil) {'''
if old_snapshot_signature not in text:
    raise SystemExit('updateActiveSnapshot signature anchor not found')
text = text.replace(old_snapshot_signature, new_snapshot_signature, 1)

old_snapshot_item = '''                displayDeviceID: device,
                rawDeviceID: device,
                activatedAt: ISO8601DateFormatter().string(from: Date())
            )
'''
new_snapshot_item = '''                displayDeviceID: device,
                rawDeviceID: device,
                activatedAt: ISO8601DateFormatter().string(from: Date()),
                deviceModel: deviceModel,
                iosVersion: iosVersion
            )
'''
if old_snapshot_item not in text:
    raise SystemExit('snapshot ActiveDeviceItem anchor not found')
text = text.replace(old_snapshot_item, new_snapshot_item, 1)

old_refresh_item = '''                        displayDeviceID: display,
                        rawDeviceID: known?.deviceID,
                        activatedAt: record?.activatedAt
                    ))
'''
new_refresh_item = '''                        displayDeviceID: display,
                        rawDeviceID: known?.deviceID,
                        activatedAt: record?.activatedAt,
                        deviceModel: record?.deviceModel,
                        iosVersion: record?.iosVersion
                    ))
'''
if old_refresh_item not in text:
    raise SystemExit('refresh ActiveDeviceItem anchor not found')
text = text.replace(old_refresh_item, new_refresh_item, 1)

# Use an iOS-16-safe SF Symbol for the Devices tab. iphone.gen3 can render blank.
text = text.replace('Label("Devices", systemImage: "iphone.gen3")', 'Label("Devices", systemImage: "iphone")')

# Surface model + iOS details directly in each active-device card.
row_anchor = '''            Text(item.displayDeviceID)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
'''
row_replacement = '''            Text(item.displayDeviceID)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
            if let modelName = item.deviceModel, !modelName.isEmpty {
                Label(modelName, systemImage: "iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let ios = item.iosVersion, !ios.isEmpty {
                Label("iOS \\(ios)", systemImage: "gearshape.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
'''
if row_anchor not in text:
    raise SystemExit('ActiveDeviceRow details anchor not found')
text = text.replace(row_anchor, row_replacement, 1)

# Also show device details in request cards before activation.
request_row_anchor = '''            Text(request.deviceID)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
'''
request_row_replacement = '''            Text(request.deviceID)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
            if let modelName = request.deviceModel, !modelName.isEmpty {
                Label(modelName, systemImage: "iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let ios = request.iosVersion, !ios.isEmpty {
                Label("iOS \\(ios)", systemImage: "gearshape.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
'''
if request_row_anchor not in text:
    raise SystemExit('RequestRow details anchor not found')
text = text.replace(request_row_anchor, request_row_replacement, 1)

text = text.replace('NSAdmin/1.0.3', 'NSAdmin/1.0.4')
text = text.replace('LabeledContent("Version", value: "1.0.3")', 'LabeledContent("Version", value: "1.0.4")')
source_path.write_text(text)

project_path = Path('NextSolutionLicenseAdmin/project.yml')
project = project_path.read_text()
project = project.replace('MARKETING_VERSION: "1.0.3"', 'MARKETING_VERSION: "1.0.4"')
project = project.replace('CURRENT_PROJECT_VERSION: "103"', 'CURRENT_PROJECT_VERSION: "104"')
project_path.write_text(project)

plist_path = Path('NextSolutionLicenseAdmin/Info.plist')
plist = plist_path.read_text()
plist = plist.replace('<key>CFBundleShortVersionString</key><string>1.0.3</string>', '<key>CFBundleShortVersionString</key><string>1.0.4</string>')
plist = plist.replace('<key>CFBundleVersion</key><string>103</string>', '<key>CFBundleVersion</key><string>104</string>')
plist_path.write_text(plist)

print('Patched NS Admin source for 1.0.4 device details and tab glyph')
