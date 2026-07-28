from pathlib import Path


def replace_required(text: str, old: str, new: str, label: str, count: int = 1) -> str:
    found = text.count(old)
    if found < count:
        raise RuntimeError(f"Could not locate {label}; expected {count}, found {found}")
    return text.replace(old, new, count)


# MARK: - Persist an optional existing-job link or a manual job reference.
models_path = Path("NextJob/Vault/VaultModels.swift")
models = models_path.read_text(encoding="utf-8")
models = replace_required(
    models,
    '''    var userID: String
    var category: String
    var notes: String''',
    '''    var userID: String
    var category: String
    var linkedJobID: UUID?
    var manualJobReference: String?
    var notes: String''',
    "vault job-link properties",
)
models = replace_required(
    models,
    '''        userID: String = "",
        category: String = "General",
        notes: String = "",''',
    '''        userID: String = "",
        category: String = "General",
        linkedJobID: UUID? = nil,
        manualJobReference: String? = nil,
        notes: String = "",''',
    "vault job-link initializer parameters",
)
models = replace_required(
    models,
    '''        self.userID = userID
        self.category = category
        self.notes = notes''',
    '''        self.userID = userID
        self.category = category
        self.linkedJobID = linkedJobID
        self.manualJobReference = manualJobReference
        self.notes = notes''',
    "vault job-link assignments",
)
models = replace_required(
    models,
    '[service, website, userID, category, notes]',
    '[service, website, userID, category, manualJobReference ?? "", notes]',
    "vault searchable text",
)
models_path.write_text(models, encoding="utf-8")


# MARK: - Existing job selector, manual reference entry and separate send button.
views_path = Path("NextJob/Vault/VaultViews.swift")
views = views_path.read_text(encoding="utf-8")

if "private enum VaultJobLinkMode" not in views:
    insertion = '''import UIKit

private enum VaultJobLinkMode: String, CaseIterable, Identifiable {
    case none
    case existing
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No Job"
        case .existing: return "Existing"
        case .manual: return "Manual"
        }
    }
}
'''
    views = replace_required(views, "import UIKit\n", insertion, "job-link mode enum")

views = replace_required(
    views,
    '''struct VaultDetailView: View {
    @EnvironmentObject private var vaultStore: VaultStore''',
    '''struct VaultDetailView: View {
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var jobStore: JobStore''',
    "JobStore in vault detail",
)
views = replace_required(
    views,
    '''    @State private var showingEditor = false
    @State private var previewURL: URL?''',
    '''    @State private var showingEditor = false
    @State private var showingSendLogin = false
    @State private var previewURL: URL?''',
    "send-login state",
)
views = replace_required(
    views,
    '''                        informationCard(entry)
                        attachmentsCard(entry)
                        dangerCard(entry)''',
    '''                        informationCard(entry)
                        attachmentsCard(entry)
                        sendLoginCard(entry)
                        dangerCard(entry)''',
    "send-login detail card",
)
views = replace_required(
    views,
    '''        .sheet(isPresented: $showingEditor) {
            if let entry {
                VaultEditorView(entry: entry)
                    .environmentObject(vaultStore)
            }
        }
        .sheet(isPresented: Binding(''',
    '''        .sheet(isPresented: $showingEditor) {
            if let entry {
                VaultEditorView(entry: entry)
                    .environmentObject(vaultStore)
            }
        }
        .sheet(isPresented: $showingSendLogin) {
            if let entry {
                VaultSendLoginView(entryID: entry.id)
                    .environmentObject(vaultStore)
                    .environmentObject(jobStore)
            }
        }
        .sheet(isPresented: Binding(''',
    "separate login send sheet",
)
views = replace_required(
    views,
    '''            detailRow("Client Name", value: entry.service.isEmpty ? "Not entered" : entry.service, action: nil)
            detailRow("Login / User ID", value: entry.userID.isEmpty ? "Not entered" : entry.userID) {''',
    '''            detailRow("Client Name", value: entry.service.isEmpty ? "Not entered" : entry.service, action: nil)
            detailRow("Connected Job", value: connectedJobText(entry), action: nil)
            detailRow("Login / User ID", value: entry.userID.isEmpty ? "Not entered" : entry.userID) {''',
    "connected-job detail row",
)

send_card_marker = '''    private func dangerCard(_ entry: VaultEntry) -> some View {
'''
send_card = '''    private func sendLoginCard(_ entry: VaultEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Send Login Details", systemImage: "paperplane.fill")
            Text("Send this login and its own attachments through Gmail. This remains separate from every job request, completion package and job email-history record.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                authenticateForSending(entry)
            } label: {
                Label("Send Login Details & Attachments", systemImage: "lock.shield.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .glassCard()
    }

    private func connectedJobText(_ entry: VaultEntry) -> String {
        if let linkedJobID = entry.linkedJobID,
           let job = jobStore.job(id: linkedJobID) {
            let client = job.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
            return client.isEmpty ? job.title : "\\(job.title) — \\(client)"
        }
        let manual = (entry.manualJobReference ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return manual.isEmpty ? "Not connected" : manual
    }

    private func authenticateForSending(_ entry: VaultEntry) {
        Task {
            if await VaultSecurity.authenticate(reason: "Authenticate to prepare the separate login-details email for \\(entry.service).") {
                showingSendLogin = true
            } else {
                showNotice("Authentication Required", "The login-details email was not opened.")
            }
        }
    }

'''
views = replace_required(views, send_card_marker, send_card + send_card_marker, "send-login card helpers")

views = replace_required(
    views,
    '''struct VaultEditorView: View {
    @EnvironmentObject private var vaultStore: VaultStore''',
    '''struct VaultEditorView: View {
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var jobStore: JobStore''',
    "JobStore in vault editor",
)
views = replace_required(
    views,
    '''    @State private var draft: VaultEntry
    @State private var password = ""''',
    '''    @State private var draft: VaultEntry
    @State private var jobLinkMode: VaultJobLinkMode
    @State private var password = ""''',
    "job-link editor state",
)
views = replace_required(
    views,
    '''    init(entry: VaultEntry? = nil) {
        originalEntry = entry
        _draft = State(initialValue: entry ?? VaultEntry())
    }''',
    '''    init(entry: VaultEntry? = nil) {
        originalEntry = entry
        let initial = entry ?? VaultEntry()
        _draft = State(initialValue: initial)
        if initial.linkedJobID != nil {
            _jobLinkMode = State(initialValue: .existing)
        } else if !(initial.manualJobReference ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            _jobLinkMode = State(initialValue: .manual)
        } else {
            _jobLinkMode = State(initialValue: .none)
        }
    }''',
    "job-link editor initialization",
)

category_section = '''                    Section("Category") {
                        TextField("Category", text: $draft.category)
                            .textInputAutocapitalization(.words)
                        if !vaultStore.sortedCategories.isEmpty {
                            Menu {
                                ForEach(vaultStore.sortedCategories, id: \.self) { category in
                                    Button(category) { draft.category = category }
                                }
                            } label: {
                                Label("Choose Existing Category", systemImage: "folder")
                            }
                        }
                        Text("A new category is created automatically when this login is saved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Attachments") {'''
replacement_section = '''                    Section("Category") {
                        TextField("Category", text: $draft.category)
                            .textInputAutocapitalization(.words)
                        if !vaultStore.sortedCategories.isEmpty {
                            Menu {
                                ForEach(vaultStore.sortedCategories, id: \.self) { category in
                                    Button(category) { draft.category = category }
                                }
                            } label: {
                                Label("Choose Existing Category", systemImage: "folder")
                            }
                        }
                        Text("A new category is created automatically when this login is saved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Connected Job or Purpose") {
                        Picker("Connection", selection: $jobLinkMode) {
                            ForEach(VaultJobLinkMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if jobLinkMode == .existing {
                            if jobStore.sortedJobs.isEmpty {
                                Text("No jobs are currently saved. Choose Manual and write the job, project or purpose yourself.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("Select Existing Job", selection: $draft.linkedJobID) {
                                    Text("Choose a job").tag(Optional<UUID>.none)
                                    ForEach(jobStore.sortedJobs) { job in
                                        let client = job.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
                                        Text(client.isEmpty ? job.title : "\\(job.title) — \\(client)")
                                            .tag(Optional(job.id))
                                    }
                                }
                            }
                        } else if jobLinkMode == .manual {
                            TextField(
                                "Manual job, project or purpose",
                                text: Binding(
                                    get: { draft.manualJobReference ?? "" },
                                    set: { draft.manualJobReference = $0 }
                                )
                            )
                            .textInputAutocapitalization(.sentences)
                            Text("Use this when the job has not been added in the Jobs tab.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("This login will remain independent and will not be connected to a job.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Attachments") {'''
views = replace_required(views, category_section, replacement_section, "connected-job editor section")

views = replace_required(
    views,
    '''    private func save() {
        do {
            try vaultStore.save(draft, password: password)''',
    '''    private func save() {
        switch jobLinkMode {
        case .none:
            draft.linkedJobID = nil
            draft.manualJobReference = nil
        case .existing:
            draft.manualJobReference = nil
            guard draft.linkedJobID != nil else {
                showNotice("Select a Job", "Choose an existing job, switch to Manual, or select No Job.")
                return
            }
        case .manual:
            draft.linkedJobID = nil
            let manual = (draft.manualJobReference ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !manual.isEmpty else {
                showNotice("Manual Reference Required", "Write the job, project or purpose, or select No Job.")
                return
            }
            draft.manualJobReference = manual
        }

        do {
            try vaultStore.save(draft, password: password)''',
    "job-link save validation",
)
views_path.write_text(views, encoding="utf-8")


# MARK: - Clean stored job-reference values and retain compatibility.
store_path = Path("NextJob/Vault/VaultStore.swift")
store = store_path.read_text(encoding="utf-8")
store = replace_required(
    store,
    '''        saved.category = cleanCategory(saved.category)
        saved.updatedAt = Date()''',
    '''        saved.category = cleanCategory(saved.category)
        saved.manualJobReference = saved.manualJobReference?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.linkedJobID != nil {
            saved.manualJobReference = nil
        }
        saved.updatedAt = Date()''',
    "job-reference cleanup",
)
store_path.write_text(store, encoding="utf-8")


# MARK: - Version metadata.
settings_path = Path("NextJob/Views/SettingsView.swift")
settings = settings_path.read_text(encoding="utf-8")
settings = replace_required(
    settings,
    'LabeledContent("Version", value: "1.0.7")',
    'LabeledContent("Version", value: "1.0.8")',
    "Settings version",
)
settings_path.write_text(settings, encoding="utf-8")

project_path = Path("NextJob/project.yml")
project = project_path.read_text(encoding="utf-8")
project = replace_required(project, 'MARKETING_VERSION: "1.0.7"', 'MARKETING_VERSION: "1.0.8"', "marketing version")
project = replace_required(project, 'CURRENT_PROJECT_VERSION: "8"', 'CURRENT_PROJECT_VERSION: "9"', "build version")
project_path.write_text(project, encoding="utf-8")

email_path = Path("NextJob/Services/EmailDeliveryService.swift")
email = email_path.read_text(encoding="utf-8")
email = replace_required(email, "NextJob-iOS/1.0.7", "NextJob-iOS/1.0.8", "email user agent", count=2)
email_path.write_text(email, encoding="utf-8")

print("Next Job 1.0.8 job-linked Secure Logins and separate login email applied.")
