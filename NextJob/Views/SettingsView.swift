import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: JobStore
    @State private var newJobType = ""
    @State private var showingAddType = false
    @State private var sharePayload: SharePayload?
    @State private var showingImporter = false
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showingNotice = false

    var body: some View {
        NavigationStack {
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
                                granted ? "Next Job can remind you 24 hours and 1 hour before a deadline." : "You can enable notifications later in iPhone Settings."
                            )
                        }
                    }
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
                    Text("These choices appear when you create or edit a job.")
                }

                Section("Backup") {
                    Button {
                        do {
                            sharePayload = SharePayload(items: [try store.exportDatabase()])
                        } catch {
                            showNotice("Backup Failed", error.localizedDescription)
                        }
                    } label: {
                        Label("Export Data Backup", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Data Backup", systemImage: "square.and.arrow.down")
                    }
                    Text("The backup contains job records and settings. Job attachment files remain visible through the iPhone Files app under Next Job.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("App", value: "Next Job")
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Author", value: "Next Solution – Zeeshan Barvi")
                    LabeledContent("Minimum iOS", value: "16.0")
                }
            }
            .navigationTitle("Settings")
            .alert("Add Job Type", isPresented: $showingAddType) {
                TextField("Job type name", text: $newJobType)
                Button("Add") {
                    store.addJobType(named: newJobType)
                    newJobType = ""
                }
                Button("Cancel", role: .cancel) { newJobType = "" }
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: payload.items)
            }
            .sheet(isPresented: $showingImporter) {
                DocumentPicker(allowsMultipleSelection: false) { result in
                    showingImporter = false
                    do {
                        guard let url = try result.get().first else { return }
                        try store.importDatabase(from: url)
                        showNotice("Import Complete", "Your saved jobs and settings have been restored.")
                    } catch {
                        showNotice("Import Failed", error.localizedDescription)
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

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
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
