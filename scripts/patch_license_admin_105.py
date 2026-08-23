from pathlib import Path


source_path = Path("NextSolutionLicenseAdmin/Sources/NextSolutionLicenseAdminApp.swift")
text = source_path.read_text()

old_products = '''    static let nextLock = ProductConfig(
        id: "nextlock",
        name: "NextLock",
        packageID: "com.nextsolution.lockglyphtime",
        registryPath: "licenses/nextlock.json",
        price: "$1.00"
    )

    static let all: [ProductConfig] = [.nextLock]
'''
new_products = '''    static let nextLock = ProductConfig(
        id: "nextlock",
        name: "NextLock",
        packageID: "com.nextsolution.lockglyphtime",
        registryPath: "licenses/nextlock.json",
        price: "$1.00"
    )

    static let moduleGlass = ProductConfig(
        id: "moduleglass",
        name: "Module Glass",
        packageID: "com.nextsolution.nextaura.cc-module-backgrounds",
        registryPath: "licenses/moduleglass.json",
        price: "$1.00"
    )

    static let all: [ProductConfig] = [.nextLock, .moduleGlass]
'''
if old_products not in text:
    raise SystemExit("ProductConfig anchor not found")
text = text.replace(old_products, new_products, 1)

old_connection = '''        do {
            let (registry, _) = try await api.loadRegistry(product: .nextLock, token: token)
            settingsStatus = "Connected. \\(registry.active.count) active NextLock license(s)."
        } catch {
'''
new_connection = '''        do {
            var counts: [String] = []
            for product in ProductConfig.all {
                let (registry, _) = try await api.loadRegistry(product: product, token: token)
                counts.append("\\(product.name): \\(registry.active.count)")
            }
            settingsStatus = "Connected. " + counts.joined(separator: " · ")
        } catch {
'''
if old_connection not in text:
    raise SystemExit("testConnection anchor not found")
text = text.replace(old_connection, new_connection, 1)

old_privacy = '''                    Text("Activation writes only the SHA-256 license token to the public registry. The raw Device ID stays in this admin app and is never added to licenses/nextlock.json.")
'''
new_privacy = '''                    Text("Activation writes only the SHA-256 license token to the selected tweak registry. The raw Device ID stays in this admin app and is never published.")
'''
if old_privacy not in text:
    raise SystemExit("activation privacy text anchor not found")
text = text.replace(old_privacy, new_privacy, 1)

text = text.replace("NSAdmin/1.0.4", "NSAdmin/1.0.5")
text = text.replace('LabeledContent("Version", value: "1.0.4")', 'LabeledContent("Version", value: "1.0.5")')
source_path.write_text(text)

project_path = Path("NextSolutionLicenseAdmin/project.yml")
project = project_path.read_text()
project = project.replace('MARKETING_VERSION: "1.0.4"', 'MARKETING_VERSION: "1.0.5"')
project = project.replace('CURRENT_PROJECT_VERSION: "104"', 'CURRENT_PROJECT_VERSION: "105"')
project_path.write_text(project)

plist_path = Path("NextSolutionLicenseAdmin/Info.plist")
plist = plist_path.read_text()
plist = plist.replace('<key>CFBundleShortVersionString</key><string>1.0.4</string>', '<key>CFBundleShortVersionString</key><string>1.0.5</string>')
plist = plist.replace('<key>CFBundleVersion</key><string>104</string>', '<key>CFBundleVersion</key><string>105</string>')
plist_path.write_text(plist)

print("Patched NS Admin 1.0.5 with Module Glass activation")
