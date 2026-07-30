from pathlib import Path


def replace_required(text: str, old: str, new: str, label: str, count: int = 1) -> str:
    found = text.count(old)
    if found < count:
        raise RuntimeError(f"Could not locate {label}; expected {count}, found {found}")
    return text.replace(old, new, count)


# MARK: - Rename the visible Service field to Client Name while retaining the
# stored `service` key so existing 1.0.6 vault records remain fully compatible.
views_path = Path("NextJob/Vault/VaultViews.swift")
views = views_path.read_text(encoding="utf-8")
views = replace_required(
    views,
    '.searchable(text: $searchText, prompt: "Search service, website, login or notes")',
    '.searchable(text: $searchText, prompt: "Search client, website, login or notes")',
    "vault search prompt",
)
views = replace_required(
    views,
    '? "Tap + to save your first service, website, login and password."',
    '? "Tap + to save your first client, website, login and password."',
    "vault empty-state message",
)
views = replace_required(
    views,
    '                    Section("Account") {\n                        TextField("Service", text: $draft.service)',
    '                    Section("Client & Account") {\n                        TextField("Client Name", text: $draft.service)',
    "client-name editor field",
)
views = replace_required(
    views,
    '            SectionTitle(title: "Login Information", systemImage: "person.text.rectangle.fill")\n            detailRow("Login / User ID", value: entry.userID.isEmpty ? "Not entered" : entry.userID) {',
    '            SectionTitle(title: "Login Information", systemImage: "person.text.rectangle.fill")\n            detailRow("Client Name", value: entry.service.isEmpty ? "Not entered" : entry.service, action: nil)\n            detailRow("Login / User ID", value: entry.userID.isEmpty ? "Not entered" : entry.userID) {',
    "client-name detail row",
)

# MARK: - Add a reliable visible Done button to every Quick Look attachment
# preview. The preview is wrapped in its own UIKit navigation controller so the
# close action remains visible for images, PDFs and other supported files.
old_preview_use = '            if let previewURL { VaultQuickLookView(url: previewURL) }'
new_preview_use = '''            if let previewURL {
                VaultQuickLookView(url: previewURL) {
                    self.previewURL = nil
                }
            }'''
views = replace_required(
    views,
    old_preview_use,
    new_preview_use,
    "Quick Look preview sheet usages",
    count=2,
)

old_quicklook = '''struct VaultQuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}'''
new_quicklook = '''struct VaultQuickLookView: UIViewControllerRepresentable {
    let url: URL
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onDone: onDone)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        preview.navigationItem.title = url.lastPathComponent
        preview.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.doneTapped)
        )
        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        let onDone: () -> Void

        init(url: URL, onDone: @escaping () -> Void) {
            self.url = url
            self.onDone = onDone
        }

        @objc func doneTapped() {
            onDone()
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}'''
views = replace_required(views, old_quicklook, new_quicklook, "Quick Look controller")
views_path.write_text(views, encoding="utf-8")


# MARK: - Client-facing sorting and validation language.
models_path = Path("NextJob/Vault/VaultModels.swift")
models = models_path.read_text(encoding="utf-8")
models = replace_required(
    models,
    'case .serviceAZ: return "Service A–Z"',
    'case .serviceAZ: return "Client Name A–Z"',
    "client-name sort title",
)
models_path.write_text(models, encoding="utf-8")

store_path = Path("NextJob/Vault/VaultStore.swift")
store = store_path.read_text(encoding="utf-8")
store = replace_required(
    store,
    'case .serviceRequired: return "Enter the service name before saving."',
    'case .serviceRequired: return "Enter the client name before saving."',
    "client-name validation message",
)
store_path.write_text(store, encoding="utf-8")


# MARK: - Version metadata.
settings_path = Path("NextJob/Views/SettingsView.swift")
settings = settings_path.read_text(encoding="utf-8")
settings = replace_required(
    settings,
    'LabeledContent("Version", value: "1.0.6")',
    'LabeledContent("Version", value: "1.0.7")',
    "Settings version",
)
settings_path.write_text(settings, encoding="utf-8")

project_path = Path("NextJob/project.yml")
project = project_path.read_text(encoding="utf-8")
project = replace_required(project, 'MARKETING_VERSION: "1.0.6"', 'MARKETING_VERSION: "1.0.7"', "marketing version")
project = replace_required(project, 'CURRENT_PROJECT_VERSION: "7"', 'CURRENT_PROJECT_VERSION: "8"', "build version")
project_path.write_text(project, encoding="utf-8")

email_path = Path("NextJob/Services/EmailDeliveryService.swift")
email = email_path.read_text(encoding="utf-8")
email = replace_required(email, "NextJob-iOS/1.0.6", "NextJob-iOS/1.0.7", "email user agent")
email_path.write_text(email, encoding="utf-8")

print("Next Job 1.0.7 client-name and attachment-preview fixes applied.")
