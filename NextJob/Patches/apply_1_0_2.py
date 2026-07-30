from pathlib import Path

service_path = Path("NextJob/Services/JobFileService.swift")
service = service_path.read_text(encoding="utf-8")
legacy_overload = '''    func copyFiles(_ urls: [URL], jobID: UUID, kind: AttachmentKind, legacy: Bool = true) throws -> [JobAttachment] {
        try copyFiles(urls, jobID: jobID, kind: kind)
    }

'''
service = service.replace(legacy_overload, "")
service_path.write_text(service, encoding="utf-8")

email_path = Path("NextJob/Services/EmailDeliveryService.swift")
email_source = email_path.read_text(encoding="utf-8")
if "    @MainActor\n    func send(\n        recipient:" not in email_source:
    email_source = email_source.replace(
        "    func send(\n        recipient:",
        "    @MainActor\n    func send(\n        recipient:",
        1,
    )
email_path.write_text(email_source, encoding="utf-8")

ai_path = Path("NextJob/Views/AIEmailView.swift")
ai_source = ai_path.read_text(encoding="utf-8")
ai_replacements = [
    ('    @State private var body = ""', '    @State private var emailBody = ""'),
    ('                body = ""', '                emailBody = ""'),
    ('            if subject.isEmpty && body.isEmpty {', '            if subject.isEmpty && emailBody.isEmpty {'),
    ('                TextEditor(text: $body)', '                TextEditor(text: $emailBody)'),
    ('                body = result.body', '                emailBody = result.body'),
    ('              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {', '              !emailBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {'),
    ('            draft: OpenAIEmailDraft(subject: subject, body: body),', '            draft: OpenAIEmailDraft(subject: subject, body: emailBody),'),
    ('detailRow("Price", "\\(store.settings.currency) \\(job.price, specifier: \"%.2f\")")', 'detailRow("Price", "\\(store.settings.currency) \\(String(format: \"%.2f\", job.price))")'),
]
for old_value, new_value in ai_replacements:
    if old_value not in ai_source:
        raise RuntimeError(f"Could not locate AI email source fragment: {old_value}")
    ai_source = ai_source.replace(old_value, new_value, 1)
ai_path.write_text(ai_source, encoding="utf-8")

view_path = Path("NextJob/Views/JobDetailView.swift")
view = view_path.read_text(encoding="utf-8")
view = view.replace(
    'Label("Add Folder", systemImage: "folder.badge.plus")',
    'Label("Add Complete Folder", systemImage: "folder.badge.plus")'
)
old = '''            let selectedKind = pickerKind
            if pickerMode == .folder {
                importMessage = "Adding folder and its contents…"
            } else {
                importMessage = "Adding \\(urls.count) selected file\\(urls.count == 1 ? "" : "s")…"
            }
            isImportingItems = true

            DispatchQueue.global(qos: .userInitiated).async {
                let importResult = Result {
                    try JobFileService.shared.copyItems(urls, jobID: jobID, kind: selectedKind)
                }
'''
new = '''            let selectedKind = pickerKind
            let selectedMode = pickerMode
            if selectedMode == .folder {
                importMessage = "Validating and adding the complete folder…"
            } else {
                importMessage = "Adding \\(urls.count) selected file\\(urls.count == 1 ? "" : "s")…"
            }
            isImportingItems = true

            DispatchQueue.global(qos: .userInitiated).async {
                let importResult = Result { () -> [JobAttachment] in
                    switch selectedMode {
                    case .folder:
                        guard urls.count == 1, let folderURL = urls.first else {
                            throw JobFileError.folderExpected
                        }
                        return [try JobFileService.shared.copyFolder(folderURL, jobID: jobID, kind: selectedKind)]
                    case .files:
                        return try JobFileService.shared.copyFiles(urls, jobID: jobID, kind: selectedKind)
                    }
                }
'''
if old not in view:
    raise RuntimeError("Could not locate the Next Job 1.0.1 import handler")
view = view.replace(old, new, 1)
view_path.write_text(view, encoding="utf-8")
