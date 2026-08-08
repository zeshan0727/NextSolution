#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:180]!r}")
    path.write_text(text.replace(old, new, 1))


def regex_once(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"Expected one regex match in {path}, found {count}: {pattern}")
    path.write_text(updated)


files = SOURCES / "FileSharing.swift"

# Preserve shortcuts by their fixed slot position so renamed titles never lose saved emails.
replace_once(
    files,
    '''    func reload() {
        let saved: [FileShareShortcut]
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([FileShareShortcut].self, from: data) {
            saved = decoded
        } else {
            saved = []
        }

        shortcuts = Self.fixedTitles.map { title in
            saved.first(where: { $0.title == title })
                ?? FileShareShortcut(title: title, email: "")
        }
    }''',
    '''    func reload() {
        let saved: [FileShareShortcut]
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([FileShareShortcut].self, from: data) {
            saved = decoded
        } else {
            saved = []
        }

        shortcuts = Self.fixedTitles.enumerated().map { index, defaultTitle in
            guard saved.indices.contains(index) else {
                return FileShareShortcut(title: defaultTitle, email: "")
            }
            let savedTitle = saved[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
            return FileShareShortcut(
                title: savedTitle.isEmpty ? defaultTitle : savedTitle,
                email: saved[index].email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }'''
)

# Hide email addresses on shortcut buttons and show a green configured check beside the name.
regex_once(
    files,
    r'''    private var recipientShortcuts: some View \{.*?\n    \}\n\n    private var toSection:''',
    '''    private var recipientShortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quick Recipients", trailing: "Tap to add to To")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(shortcutStore.shortcuts.indices, id: \\.self) { index in
                    let shortcut = shortcutStore.shortcuts[index]
                    let configured = FileShareService.isValidEmail(shortcut.email)

                    Button {
                        if configured {
                            addRecipient(shortcut.email)
                        } else {
                            isShowingShortcutEditor = true
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: configured ? "envelope.fill" : "person.crop.circle.badge.plus")
                                .font(.title3)
                                .foregroundStyle(configured ? Color.green : Color.nextOrange)

                            HStack(spacing: 5) {
                                Text(shortcut.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                if configured {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }

                            Text(configured ? "Ready" : "Set email")
                                .font(.caption2.bold())
                                .foregroundStyle(configured ? Color.green : Color.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(configured ? Color.green.opacity(0.35) : Color.nextCardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var toSection:'''
)

# Allow both shortcut names and email addresses to be edited with validation.
regex_once(
    files,
    r'''struct FileShareShortcutEditor: View \{.*?\n\}\n\nstruct CameraCaptureView:''',
    '''struct FileShareShortcutEditor: View {
    @Environment(\\.dismiss) private var dismiss
    @ObservedObject var store: FileShareShortcutStore
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.shortcuts.indices, id: \\.self) { index in
                        let configured = FileShareService.isValidEmail(store.shortcuts[index].email)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Shortcut \\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if configured {
                                    Label("Email saved", systemImage: "checkmark.circle.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(.green)
                                }
                            }

                            TextField("Button name", text: $store.shortcuts[index].title)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(Color.nextBackground, in: RoundedRectangle(cornerRadius: 11))

                            TextField("email@example.com", text: $store.shortcuts[index].email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .padding(12)
                                .background(Color.nextBackground, in: RoundedRectangle(cornerRadius: 11))
                        }
                        .padding(14)
                        .nextCard()
                    }
                }
                .padding(16)
            }
            .background(Color.nextBackground.ignoresSafeArea())
            .navigationTitle("Recipient Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.reload()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveShortcuts()
                    }
                }
            }
            .alert("Recipient Shortcuts", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func saveShortcuts() {
        var cleaned = store.shortcuts
        for index in cleaned.indices {
            let trimmedTitle = cleaned[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultTitle = FileShareShortcutStore.fixedTitles.indices.contains(index)
                ? FileShareShortcutStore.fixedTitles[index]
                : "Shortcut \\(index + 1)"
            cleaned[index].title = trimmedTitle.isEmpty ? defaultTitle : trimmedTitle

            let trimmedEmail = cleaned[index].email.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedEmail.isEmpty && !FileShareService.isValidEmail(trimmedEmail) {
                errorMessage = "Enter a valid email address for \\(cleaned[index].title)."
                return
            }
            cleaned[index].email = trimmedEmail
        }

        store.shortcuts = cleaned
        store.save()
        dismiss()
    }
}

struct CameraCaptureView:'''
)

# Version metadata and client identifiers.
project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.2.4"', 'CFBundleShortVersionString: "1.2.5"')
project_text = project_text.replace('CFBundleVersion: "8"', 'CFBundleVersion: "9"')
project_text = project_text.replace('MARKETING_VERSION: "1.2.4"', 'MARKETING_VERSION: "1.2.5"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "8"', 'CURRENT_PROJECT_VERSION: "9"')
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.2.4 • iOS 16.0+", "Version 1.2.5 • iOS 16.0+"))

for name in ["EmailAutomationCore.swift", "GmailConnection.swift", "FileSharing.swift"]:
    path = SOURCES / name
    path.write_text(path.read_text().replace("NextReminder-iOS/1.2.4", "NextReminder-iOS/1.2.5"))

print("Next Reminder v1.2.5 patches applied successfully.")
