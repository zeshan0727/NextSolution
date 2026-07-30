from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Could not locate {label} in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# MARK: - Dedicated Secure Logins tab.
root_path = Path("NextJob/Views/AppRootView.swift")
root = root_path.read_text(encoding="utf-8")
if "VaultStore.shared" not in root:
    root = root.replace(
        "    @StateObject private var emailDraftStore = EmailDraftStore()\n",
        "    @StateObject private var emailDraftStore = EmailDraftStore()\n    @StateObject private var vaultStore = VaultStore.shared\n",
        1,
    )

old_tabs = '''                EmailCenterView()
                    .environmentObject(emailDraftStore)
                    .tabItem { Label("Email", systemImage: "envelope.fill") }
                    .tag(2)

                AIEmailView()
                    .environmentObject(emailDraftStore)
                    .tabItem { Label("AI", systemImage: "sparkles") }
                    .tag(3)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(4)'''
new_tabs = '''                VaultView()
                    .environmentObject(vaultStore)
                    .tabItem { Label("Logins", systemImage: "lock.shield.fill") }
                    .tag(2)

                EmailCenterView()
                    .environmentObject(emailDraftStore)
                    .tabItem { Label("Email", systemImage: "envelope.fill") }
                    .tag(3)

                AIEmailView()
                    .environmentObject(emailDraftStore)
                    .tabItem { Label("AI", systemImage: "sparkles") }
                    .tag(4)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(5)'''
if old_tabs not in root:
    raise RuntimeError("Could not insert the Secure Logins tab")
root = root.replace(old_tabs, new_tabs, 1)
root_path.write_text(root, encoding="utf-8")


# MARK: - Camera and biometric permission descriptions.
info_path = Path("NextJob/Info.plist")
info = info_path.read_text(encoding="utf-8")
if "NSCameraUsageDescription" not in info:
    marker = '''    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>'''
    replacement = '''    <key>NSCameraUsageDescription</key>
    <string>Next Job uses the camera to attach protected account screenshots and documents to Secure Logins.</string>
    <key>NSFaceIDUsageDescription</key>
    <string>Face ID protects password reveal, copying and editing inside Secure Logins.</string>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>'''
    if marker not in info:
        raise RuntimeError("Could not add Secure Logins permission descriptions")
    info = info.replace(marker, replacement, 1)
info_path.write_text(info, encoding="utf-8")


# MARK: - Version metadata and Gmail user agent.
settings_path = Path("NextJob/Views/SettingsView.swift")
settings = settings_path.read_text(encoding="utf-8")
settings = settings.replace('LabeledContent("Version", value: "1.0.5")', 'LabeledContent("Version", value: "1.0.6")')
settings_path.write_text(settings, encoding="utf-8")

project_path = Path("NextJob/project.yml")
project = project_path.read_text(encoding="utf-8")
project = project.replace('MARKETING_VERSION: "1.0.5"', 'MARKETING_VERSION: "1.0.6"')
project = project.replace('CURRENT_PROJECT_VERSION: "6"', 'CURRENT_PROJECT_VERSION: "7"')
project_path.write_text(project, encoding="utf-8")

email_path = Path("NextJob/Services/EmailDeliveryService.swift")
email = email_path.read_text(encoding="utf-8")
email = email.replace("NextJob-iOS/1.0.5", "NextJob-iOS/1.0.6")
email_path.write_text(email, encoding="utf-8")

print("Next Job 1.0.6 secure Logins vault applied.")
