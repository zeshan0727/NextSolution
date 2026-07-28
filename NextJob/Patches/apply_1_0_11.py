from pathlib import Path


root_path = Path("NextJob/Views/AppRootView.swift")
root = root_path.read_text(encoding="utf-8")
if "EmailCenterV111()" not in root:
    if "EmailCenterView()" not in root:
        raise RuntimeError("Could not locate the Email tab in AppRootView")
    root = root.replace("EmailCenterView()", "EmailCenterV111()", 1)
root_path.write_text(root, encoding="utf-8")

settings_path = Path("NextJob/Views/SettingsView.swift")
settings = settings_path.read_text(encoding="utf-8")
if 'LabeledContent("Version", value: "1.0.11")' not in settings:
    if 'LabeledContent("Version", value: "1.0.10")' not in settings:
        raise RuntimeError("Could not locate the visible 1.0.10 version")
    settings = settings.replace(
        'LabeledContent("Version", value: "1.0.10")',
        'LabeledContent("Version", value: "1.0.11")',
        1,
    )
settings_path.write_text(settings, encoding="utf-8")

project_path = Path("NextJob/project.yml")
project = project_path.read_text(encoding="utf-8")
project = project.replace('MARKETING_VERSION: "1.0.10"', 'MARKETING_VERSION: "1.0.11"')
project = project.replace('CURRENT_PROJECT_VERSION: "11"', 'CURRENT_PROJECT_VERSION: "12"')
project_path.write_text(project, encoding="utf-8")

email_path = Path("NextJob/Services/EmailDeliveryService.swift")
email = email_path.read_text(encoding="utf-8")
email = email.replace("NextJob-iOS/1.0.10", "NextJob-iOS/1.0.11")
email_path.write_text(email, encoding="utf-8")

print("Next Job 1.0.11 manual email attachments applied.")
