from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Could not locate {label} in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# Version the App Store preparation build.
project_path = Path("NextJob/project.yml")
project = project_path.read_text(encoding="utf-8")
if 'MARKETING_VERSION: "1.0.12"' not in project:
    raise RuntimeError("Could not locate marketing version 1.0.12")
project = project.replace('MARKETING_VERSION: "1.0.12"', 'MARKETING_VERSION: "1.0.13"', 1)
project = project.replace('CURRENT_PROJECT_VERSION: "13"', 'CURRENT_PROJECT_VERSION: "14"', 1)
project_path.write_text(project, encoding="utf-8")

settings_path = Path("NextJob/Views/SettingsView.swift")
settings = settings_path.read_text(encoding="utf-8")
if 'LabeledContent("Version", value: "1.0.12")' not in settings:
    raise RuntimeError("Could not locate visible version 1.0.12")
settings = settings.replace(
    'LabeledContent("Version", value: "1.0.12")',
    'LabeledContent("Version", value: "1.0.13")',
    1,
)
settings_path.write_text(settings, encoding="utf-8")

email_service_path = Path("NextJob/Services/EmailDeliveryService.swift")
email_service = email_service_path.read_text(encoding="utf-8")
email_service = email_service.replace("NextJob-iOS/1.0.12", "NextJob-iOS/1.0.13")
email_service_path.write_text(email_service, encoding="utf-8")

# App Review requires purpose strings before camera/photo-library access.
info_path = Path("NextJob/Info.plist")
info = info_path.read_text(encoding="utf-8")
anchor = '''    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
'''
permission_block = '''    <key>NSCameraUsageDescription</key>
    <string>Next Job uses the camera only when you choose to photograph and attach a document to a job or secure login.</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Next Job lets you select existing photos to attach to a job or secure login.</string>
    <key>NSPhotoLibraryAddUsageDescription</key>
    <string>Next Job can save an exported document or image to your photo library when you choose that action.</string>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
'''
if anchor not in info:
    raise RuntimeError("Could not locate encryption declaration in Info.plist")
info = info.replace(anchor, permission_block, 1)
info_path.write_text(info, encoding="utf-8")

print("Next Job 1.0.13 App Store preparation applied.")
