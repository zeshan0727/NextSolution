import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: JobStore
    @StateObject private var emailConfiguration = EmailConfigurationStore.shared
    @StateObject private var openAIConfiguration = OpenAIConfigurationStore.shared

    @State private var newJobType = ""
    @State private var showingAddType = false
    @State private var backupURL: URL?
    @State private var showingBackupExporter = false
    @State private var showingRestorePicker = false
    @State private var isWorking = false
    @State private var workingMessage = "Preparing complete backup…"
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showingNotice = false

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section("KB Accountants") {
                        TextField("Company name", text: settingBinding(\.companyName))
                        TextField("Company email", text: settingBinding(\.companyEmail))
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Currency", text: settingBinding(\.currency))
                            .textInputAutocapitalization(.characters)
                    }

                    Section("Appearance") {
                        Picker("Theme", selection: settingBinding(\.theme)) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(theme.title).tag(theme)
                            }
                        }
                    }

                    Section("Deadline Reminders") {
                        Toggle("Due-date reminders", isOn: settingBinding(\.dueRemindersEnabled))
                        Button("Allow Notifications") {
                            Task {
                                let granted = await store.requestReminderPermission()
                                showNotice(
                                    granted ? "Notifications Enabled" : "Permission Not Granted",
                                    granted
                                        ? "Next Job can remind you 24 hours and 1 hour before a deadline."
                                        : "You can enable notifications later in iPhone Settings."
                                )
                            }
                        }
                    }

                    Section {
                        NavigationLink {
                            EmailSetupView()
                        } label: {
                            Label("Email & Gmail Setup", systemImage: "envelope.badge.fill")
                        }
                        LabeledContent(
                            "Gmail",
                            value: emailConfiguration.isGmailConnected
                                ? emailConfiguration.configuration.connectedEmail
                                : "Not connected"
                        )
                    } header: {
                        Text("Email")
                    } footer: {
                        Text("Uses the same secure scheduler and Gmail OAuth workflow as Next Reminder. Apple Mail assisted sending remains available.")
                    }

                    Section {
                        NavigationLink {
                            OpenAISetupView()
                        } label: {
                            Label("OpenAI Email Setup", systemImage: "sparkles")
                        }
                        LabeledContent(
                            "Status",
                            value: openAIConfiguration.isConfigured ? "Ready" : "Setup required"
                        )
                        LabeledContent("Model", value: openAIConfiguration.model)
                    } header: {
                        Text("AI")
                    } footer: {
                        Text("OpenAI receives only the selected job context when you request an email draft. API credentials are excluded from backups.")
                    }

                    Section {
                        ForEach(store.settings.jobTypes) { type in
                            Text(type.name)
                        }
                        .onDelete(perform: store.deleteJobTypes)

                        Button {
                            showingAddType = true
                        } label: {
                            Label("Add Job Type", systemImage: "plus.circle.fill")
                        }
                    } header: {
                        Text("Job Types")
                    } footer: {
                        Text("You can also create a missing job type directly while adding a new job.")
                    }

                    Section {
                        Button {
                            createCompleteBackup()
                        } label: {
                            Label("Back Up to Google Drive", systemImage: "externaldrive.badge.icloud")
                        }

                        Button {
                            showingRestorePicker = true
                        } label: {
                            Label("Restore from Google Drive", systemImage: "arrow.down.doc.fill")
                        }

                        Text("One complete backup contains all jobs, settings, related files, completion documents, and imported folder structures. Choose Google Drive in the iOS Files location list when saving or restoring.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Complete Backup & Restore")
                    } footer: {
                        Text("Restore is validated in a temporary area first. Existing data is replaced only after every attachment has been reconstructed successfully.")
                    }

                    Section("About") {
                        LabeledContent("App", value: "Next Job")
                        LabeledContent("Version", value: "1.0.2")
                        LabeledContent("Author", value: "Next Solution – Zeeshan Barvi")
                        LabeledContent("Minimum iOS", value: "16.0")
                    }
                }
                .navigationTitle("Settings")

                if isWorking {
                    Color.black.opacity(0.22).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text(workingMessage)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(32)
                }
            }
            .alert("Add Job Type", isPresented: $showingAddType) {
                TextField("Job type name", text: $newJobType)
                Button("Add") {
                    store.addJobType(named: newJobType)
                    newJobType = ""
                }
                Button("Cancel", role: .cancel) { newJobType = "" }
            }
            .sheet(isPresented: $showingBackupExporter) {
                if let backupURL {
                    BackupExportPicker(url: backupURL) { success in
                        showingBackupExporter = false
                        if success {
                            showNotice(
                                "Backup Saved",
                                "The complete Next Job backup was saved to the selected Files location."
                            )
                        }
                    }
                }
            }
            .sheet(isPresented: $showingRestorePicker) {
                DocumentPicker(mode: .files, allowsMultipleSelection: false) { result in
                    showingRestorePicker = false
                    do {
                        guard let url = try result.get().first else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            restoreCompleteBackup(from: url)
                        }
                    } catch {
                        showNotice("Restore Failed", error.localizedDescription)
                    }
                }
            }
            .alert(noticeTitle, isPresented: $showingNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(noticeMessage)
            }
        }
    }

    private func createCompleteBackup() {
        workingMessage = "Preparing jobs and all attachments…"
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                backupURL = try await store.exportCompleteBackup()
                showingBackupExporter = true
            } catch {
                showNotice("Backup Failed", error.localizedDescription)
            }
        }
    }

    private func restoreCompleteBackup(from url: URL) {
        workingMessage = "Validating and restoring every job attachment…"
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let summary = try await store.restoreCompleteBackup(from: url)
                let size = ByteCountFormatter.string(
                    fromByteCount: summary.attachmentBytes,
                    countStyle: .file
                )
                showNotice(
                    "Restore Complete",
                    "Restored \(summary.jobCount) jobs and \(summary.attachmentFileCount) attachment files (\(size))."
                )
            } catch {
                showNotice("Restore Failed", error.localizedDescription)
            }
        }
    }

    private func settingBinding<Value>(
        _ keyPath: WritableKeyPath<AppSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in
                store.updateSettings { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func showNotice(_ title: String, _ message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }
}
