from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Could not locate {label} in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


email_view_path = Path("NextJob/Views/EmailCenterV111.swift")
email_view = email_view_path.read_text(encoding="utf-8")

old_editor = '''            TextEditor(text: $draftStore.body)
                .frame(minHeight: 190)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
'''
new_editor = '''            EmailFormattingEditor(text: $draftStore.body)
'''
if old_editor not in email_view:
    raise RuntimeError("Could not locate the manual email TextEditor")
email_view = email_view.replace(old_editor, new_editor, 1)

old_importer = '''            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                importFiles(result)
            }
'''
new_importer = '''            .sheet(isPresented: $showingFileImporter) {
                DocumentPicker(mode: .files, allowsMultipleSelection: true) { result in
                    showingFileImporter = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        importFiles(result)
                    }
                }
            }
'''
if old_importer not in email_view:
    raise RuntimeError("Could not locate the manual email Files importer")
email_view = email_view.replace(old_importer, new_importer, 1)

old_import_function = '''    private func importFiles(_ result: Result<[URL], Error>) {
        do {
'''
new_import_function = '''    private func importFiles(_ result: Result<[URL], Error>) {
        showingFileImporter = false
        do {
'''
if old_import_function not in email_view:
    raise RuntimeError("Could not locate the manual email file import function")
email_view = email_view.replace(old_import_function, new_import_function, 1)

email_view_path.write_text(email_view, encoding="utf-8")

settings_path = Path("NextJob/Views/SettingsView.swift")
settings = settings_path.read_text(encoding="utf-8")
if 'LabeledContent("Version", value: "1.0.11")' not in settings:
    raise RuntimeError("Could not locate the visible 1.0.11 version")
settings = settings.replace(
    'LabeledContent("Version", value: "1.0.11")',
    'LabeledContent("Version", value: "1.0.12")',
    1,
)
settings_path.write_text(settings, encoding="utf-8")

project_path = Path("NextJob/project.yml")
project = project_path.read_text(encoding="utf-8")
if 'MARKETING_VERSION: "1.0.11"' not in project:
    raise RuntimeError("Could not locate marketing version 1.0.11")
project = project.replace('MARKETING_VERSION: "1.0.11"', 'MARKETING_VERSION: "1.0.12"', 1)
project = project.replace('CURRENT_PROJECT_VERSION: "12"', 'CURRENT_PROJECT_VERSION: "13"', 1)
project_path.write_text(project, encoding="utf-8")

email_service_path = Path("NextJob/Services/EmailDeliveryService.swift")
email_service = email_service_path.read_text(encoding="utf-8")
email_service = email_service.replace("NextJob-iOS/1.0.11", "NextJob-iOS/1.0.12")
email_service_path.write_text(email_service, encoding="utf-8")

print("Next Job 1.0.12 Files picker and email formatting applied.")
