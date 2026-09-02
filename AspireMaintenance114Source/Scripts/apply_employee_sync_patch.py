from pathlib import Path

root = Path('AspireMaintenance114Source')

# Backward-compatible employee-safe site fields.
model = root / 'ModelsAndStore.swift'
text = model.read_text()
old = '''    var name: String
    var address: String
    var email: String
'''
new = '''    var name: String
    var address: String
    var villaNumber: String? = nil
    var area: String? = nil
    var email: String
'''
if 'var villaNumber: String?' not in text:
    if old not in text:
        raise SystemExit('Customer field anchor not found')
    text = text.replace(old, new, 1)
model.write_text(text)

# Foreground and periodic cloud visit sync.
app = root / 'AspireMaintenanceApp.swift'
text = app.read_text()
old = '''        WindowGroup {
            AppRootView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await store.refreshOverdueNotifications() }
            }
        }
'''
new = '''        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .task {
                    await store.syncEmployeeVisitCloud()
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 20_000_000_000)
                        await store.syncEmployeeVisitCloud()
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task {
                    await store.refreshOverdueNotifications()
                    await store.syncEmployeeVisitCloud()
                }
            }
        }
'''
if 'while !Task.isCancelled' not in text:
    if old not in text:
        raise SystemExit('App sync anchor not found')
    text = text.replace(old, new, 1)
app.write_text(text)

views = root / 'Views.swift'
text = views.read_text()

old = '''        return store.customers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText) ||
            $0.phone.localizedCaseInsensitiveContains(searchText)
        }
'''
new = '''        return store.customers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.villaNumber ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.area ?? "").localizedCaseInsensitiveContains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText) ||
            $0.phone.localizedCaseInsensitiveContains(searchText)
        }
'''
if '($0.villaNumber ?? "").localizedCaseInsensitiveContains(searchText)' not in text:
    if old not in text:
        raise SystemExit('Customer search anchor not found')
    text = text.replace(old, new, 1)

old = '''                            LabeledValue(icon: "mappin.and.ellipse", value: customer.address.isEmpty ? "No address" : customer.address)
                            LabeledValue(icon: "phone.fill", value: customer.phone.isEmpty ? "No phone" : customer.phone)
'''
new = '''                            LabeledValue(icon: "house.fill", value: (customer.villaNumber ?? "").isEmpty ? "Villa number not set" : "Villa \\(customer.villaNumber ?? "")")
                            LabeledValue(icon: "map.fill", value: (customer.area ?? "").isEmpty ? "Area not set" : (customer.area ?? ""))
                            LabeledValue(icon: "mappin.and.ellipse", value: customer.address.isEmpty ? "No address" : customer.address)
                            LabeledValue(icon: "phone.fill", value: customer.phone.isEmpty ? "No phone" : customer.phone)
'''
if 'value: (customer.villaNumber ?? "").isEmpty ? "Villa number not set"' not in text:
    if old not in text:
        raise SystemExit('Customer site detail anchor not found')
    text = text.replace(old, new, 1)

old = '''    @State private var name = ""
    @State private var address = ""
    @State private var email = ""
'''
new = '''    @State private var name = ""
    @State private var address = ""
    @State private var villaNumber = ""
    @State private var area = ""
    @State private var email = ""
'''
if '@State private var villaNumber = ""' not in text:
    if old not in text:
        raise SystemExit('Customer editor state anchor not found')
    text = text.replace(old, new, 1)

old = '''                    TextField("Customer name", text: $name)
                    TextField("Site address", text: $address, axis: .vertical).lineLimit(2...4)
                    TextField("Email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
'''
new = '''                    TextField("Customer name", text: $name)
                    TextField("Villa number", text: $villaNumber)
                    TextField("Area", text: $area)
                    TextField("Site address", text: $address, axis: .vertical).lineLimit(2...4)
                    TextField("Email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
'''
if 'TextField("Villa number", text: $villaNumber)' not in text:
    if old not in text:
        raise SystemExit('Customer editor field anchor not found')
    text = text.replace(old, new, 1)

old = '''                name = existing.name
                address = existing.address
                email = existing.email
'''
new = '''                name = existing.name
                address = existing.address
                villaNumber = existing.villaNumber ?? ""
                area = existing.area ?? ""
                email = existing.email
'''
if 'villaNumber = existing.villaNumber ?? ""' not in text:
    if old not in text:
        raise SystemExit('Customer editor load anchor not found')
    text = text.replace(old, new, 1)

old = '''            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
'''
new = '''            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            villaNumber: villaNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : villaNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            area: area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : area.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
'''
if 'villaNumber: villaNumber.trimmingCharacters' not in text:
    if old not in text:
        raise SystemExit('Customer save anchor not found')
    text = text.replace(old, new, 1)

old = '''                Text(customer.email.isEmpty ? customer.phone : customer.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\\(customer.plannedVisitsPerMonth) visits/month")
'''
new = '''                if !(customer.villaNumber ?? "").isEmpty || !(customer.area ?? "").isEmpty {
                    Text([
                        (customer.villaNumber ?? "").isEmpty ? nil : "Villa \\(customer.villaNumber ?? "")",
                        (customer.area ?? "").isEmpty ? nil : customer.area
                    ].compactMap { $0 }.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(customer.email.isEmpty ? customer.phone : customer.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\\(customer.plannedVisitsPerMonth) visits/month")
'''
if '].compactMap { $0 }.joined(separator: " • ")' not in text:
    if old not in text:
        raise SystemExit('Customer row anchor not found')
    text = text.replace(old, new, 1)

views.write_text(text)

project = root / 'project.yml'
text = project.read_text()
text = text.replace('bundleIdPrefix: com.aspiregroup', 'bundleIdPrefix: com.nextsolution')
text = text.replace('MARKETING_VERSION: "1.0.0"', 'MARKETING_VERSION: "1.1.5"')
text = text.replace('CURRENT_PROJECT_VERSION: "1"', 'CURRENT_PROJECT_VERSION: "8"')
text = text.replace('PRODUCT_BUNDLE_IDENTIFIER: com.aspiregroup.maintenance', 'PRODUCT_BUNDLE_IDENTIFIER: com.nextsolution.aspire')
if 'CODE_SIGN_ENTITLEMENTS: AspireMaintenance.entitlements' not in text:
    text = text.replace('        INFOPLIST_FILE: Info.plist\n', '        INFOPLIST_FILE: Info.plist\n        CODE_SIGN_ENTITLEMENTS: AspireMaintenance.entitlements\n', 1)
project.write_text(text)

print('Aspire employee sync patch applied')
