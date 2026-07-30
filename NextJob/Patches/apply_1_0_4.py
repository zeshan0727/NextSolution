from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Could not locate {label} in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# MARK: - Gmail connector recovery.
email_path = Path("NextJob/Services/EmailDeliveryService.swift")
email = email_path.read_text(encoding="utf-8")

if "nextJobGmailConnectionInvalidated" not in email:
    old = '''    func clearConnection() {
        update {
            $0.connectorID = ""
            $0.connectedEmail = ""
        }
    }

    private func saveConfiguration() {'''
    new = '''    func clearConnection(reason: String? = nil) {
        update {
            $0.connectorID = ""
            $0.connectedEmail = ""
        }
        NotificationCenter.default.post(
            name: .nextJobGmailConnectionInvalidated,
            object: reason
        )
    }

    @discardableResult
    func invalidateIfStale(_ message: String, connectorID: String? = nil) -> Bool {
        let lowered = message.lowercased()
        let stale = lowered.contains("gmail connector not found")
            || lowered.contains("connector not found")
            || lowered.contains("reconnect gmail")
            || lowered.contains("reconnect the gmail account")
        guard stale else { return false }
        if let connectorID,
           !configuration.connectorID.isEmpty,
           configuration.connectorID != connectorID {
            return false
        }
        clearConnection(reason: message)
        return true
    }

    private func saveConfiguration() {'''
    if old not in email:
        raise RuntimeError("Could not add Gmail invalidation to EmailConfigurationStore")
    email = email.replace(old, new, 1)

    marker = '''}

struct GmailConnectionRecord: Codable, Equatable {'''
    replacement = '''}

extension Notification.Name {
    static let nextJobGmailConnectionInvalidated = Notification.Name(
        "NextJob.GmailConnectionInvalidated"
    )
}

struct GmailConnectionRecord: Codable, Equatable {'''
    if marker not in email:
        raise RuntimeError("Could not add Gmail invalidation notification")
    email = email.replace(marker, replacement, 1)

# Replace disconnect so a missing remote connector is treated as disconnected and
# never traps the app in an obsolete local state.
disconnect_start = email.find("    func disconnect(using store: EmailConfigurationStore) async throws {")
disconnect_end = email.find("\n    func presentationAnchor", disconnect_start)
if disconnect_start < 0 or disconnect_end < 0:
    raise RuntimeError("Could not locate Gmail disconnect function")
email = email[:disconnect_start] + '''    func disconnect(using store: EmailConfigurationStore) async throws {
        let connectorID = store.configuration.connectorID
        guard !connectorID.isEmpty else {
            store.clearConnection()
            return
        }

        let encoded = connectorID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? connectorID
        let request = try makeRequest(
            path: "v1/connectors/gmail/\\(encoded)",
            method: "DELETE",
            store: store
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GmailConnectionError.invalidResponse
        }
        if (200...299).contains(http.statusCode) {
            store.clearConnection()
            return
        }

        let message = (try? JSONDecoder().decode(GmailStartResponse.self, from: data).message)
            ?? "Gmail disconnect failed (\\(http.statusCode))."
        if http.statusCode == 404 || store.invalidateIfStale(message, connectorID: connectorID) {
            store.clearConnection(reason: message)
            return
        }
        throw GmailConnectionError.server(message)
    }
''' + email[disconnect_end:]

# Add a dedicated expired-connector error for direct sending.
email = email.replace(
    '''    case gmailNotReady
    case invalidRecipient''',
    '''    case gmailNotReady
    case connectorExpired
    case invalidRecipient''',
    1,
)
email = email.replace(
    '''        case .gmailNotReady:
            return "Connect Gmail and save the scheduler settings before sending directly."
        case .invalidRecipient:''',
    '''        case .gmailNotReady:
            return "Connect Gmail and save the scheduler settings before sending directly."
        case .connectorExpired:
            return "The saved Gmail connector no longer exists on the scheduler. The old connection was cleared; open Email Setup and connect Gmail again."
        case .invalidRecipient:''',
    1,
)

old_send_error = '''        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(DirectEmailResponse.self, from: data).message)
                ?? "Email sending failed (\\(http.statusCode))."
            throw DirectEmailError.server(message)
        }'''
new_send_error = '''        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(DirectEmailResponse.self, from: data).message)
                ?? "Email sending failed (\\(http.statusCode))."
            if store.invalidateIfStale(message, connectorID: configuration.connectorID) {
                throw DirectEmailError.connectorExpired
            }
            throw DirectEmailError.server(message)
        }'''
if old_send_error not in email:
    raise RuntimeError("Could not update direct Gmail send error handling")
email = email.replace(old_send_error, new_send_error, 1)
email = email.replace("NextJob-iOS/1.0.2", "NextJob-iOS/1.0.4")
email = email.replace("NextJob-iOS/1.0.3", "NextJob-iOS/1.0.4")
email_path.write_text(email, encoding="utf-8")


# MARK: - Gmail setup UI with reconnect and local reset actions.
setup_path = Path("NextJob/Views/EmailSetupView.swift")
setup = setup_path.read_text(encoding="utf-8")
old_connected = '''                if emailStore.isGmailConnected {
                    Label(emailStore.configuration.connectedEmail, systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Button(role: .destructive) {
                        disconnectGmail()
                    } label: {
                        Label(isDisconnecting ? "Disconnecting…" : "Disconnect Gmail", systemImage: "link.badge.minus")
                    }
                    .disabled(isDisconnecting)
                } else {'''
new_connected = '''                if emailStore.isGmailConnected {
                    Label(emailStore.configuration.connectedEmail, systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)

                    Button {
                        reconnectGmail()
                    } label: {
                        Label(isConnecting ? "Reconnecting Gmail…" : "Reconnect Gmail Account", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isConnecting || isDisconnecting || !emailStore.isSchedulerConfigured)

                    Button(role: .destructive) {
                        disconnectGmail()
                    } label: {
                        Label(isDisconnecting ? "Disconnecting…" : "Disconnect Gmail", systemImage: "link.badge.minus")
                    }
                    .disabled(isDisconnecting || isConnecting)

                    Button(role: .destructive) {
                        emailStore.clearConnection(reason: "Saved Gmail connection removed manually.")
                        showNotice("Saved Connection Removed", "The local Gmail connector was cleared. You can connect Gmail again now.")
                    } label: {
                        Label("Forget Saved Connection", systemImage: "trash")
                    }
                    .disabled(isDisconnecting || isConnecting)
                } else {'''
if old_connected not in setup:
    raise RuntimeError("Could not update connected Gmail setup controls")
setup = setup.replace(old_connected, new_connected, 1)

old_connect = '''    private func connectGmail() {
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                let record = try await GmailOAuthClient.shared.connect(using: emailStore)
                showNotice("Gmail Connected", record.emailAddress)
            } catch {
                showNotice("Gmail Connection Failed", error.localizedDescription)
            }
        }
    }

    private func disconnectGmail() {'''
new_connect = '''    private func connectGmail() {
        startGmailConnection(clearExisting: false)
    }

    private func reconnectGmail() {
        startGmailConnection(clearExisting: true)
    }

    private func startGmailConnection(clearExisting: Bool) {
        guard emailStore.isSchedulerConfigured else {
            showNotice("Scheduler Setup Required", "Save the scheduler URL and API key before connecting Gmail.")
            return
        }
        if clearExisting {
            emailStore.clearConnection(reason: "Reconnect requested by user.")
        }
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                let record = try await GmailOAuthClient.shared.connect(using: emailStore)
                showNotice("Gmail Connected", record.emailAddress)
            } catch {
                showNotice("Gmail Connection Failed", error.localizedDescription)
            }
        }
    }

    private func disconnectGmail() {'''
if old_connect not in setup:
    raise RuntimeError("Could not update Gmail connect functions")
setup = setup.replace(old_connect, new_connect, 1)

old_disconnect_catch = '''            } catch {
                showNotice("Could Not Disconnect", error.localizedDescription)
            }
        }
    }'''
new_disconnect_catch = '''            } catch {
                emailStore.clearConnection(reason: error.localizedDescription)
                showNotice(
                    "Local Connection Cleared",
                    "The scheduler could not confirm disconnection, but the saved connector was removed from Next Job. You can connect Gmail again."
                )
            }
        }
    }'''
if old_disconnect_catch not in setup:
    raise RuntimeError("Could not update Gmail disconnect recovery")
setup = setup.replace(old_disconnect_catch, new_disconnect_catch, 1)
setup_path.write_text(setup, encoding="utf-8")


# MARK: - Pending-payment filter in Jobs.
jobs_path = Path("NextJob/Views/JobsView.swift")
jobs = jobs_path.read_text(encoding="utf-8")
if "case pendingPayments" not in jobs:
    jobs = jobs.replace(
        '''    case completed
    case overdue''',
        '''    case completed
    case pendingPayments
    case overdue''',
        1,
    )
    jobs = jobs.replace(
        '''        case .completed: return "Completed"
        case .overdue: return "Overdue"''',
        '''        case .completed: return "Completed"
        case .pendingPayments: return "Pending Payments"
        case .overdue: return "Overdue"''',
        1,
    )
    jobs = jobs.replace(
        '''            case .completed: matchesFilter = job.status == .completed
            case .overdue: matchesFilter = job.isOverdue''',
        '''            case .completed: matchesFilter = job.status == .completed
            case .pendingPayments:
                matchesFilter = job.status == .completed
                    && job.price > 0
                    && job.effectivePaymentStatus == .pending
            case .overdue: matchesFilter = job.isOverdue''',
        1,
    )
jobs_path.write_text(jobs, encoding="utf-8")


# MARK: - Pending Payments dashboard section.
dashboard_path = Path("NextJob/Views/DashboardView.swift")
dashboard = dashboard_path.read_text(encoding="utf-8")
if 'title: "Pending Payments"' not in dashboard:
    marker = '''                            jobsSection(
                                title: "Recently Completed",'''
    section = '''                            jobsSection(
                                title: "Pending Payments",
                                systemImage: "banknote.fill",
                                jobs: Array(
                                    store.jobs
                                        .filter {
                                            $0.status == .completed
                                                && $0.price > 0
                                                && $0.effectivePaymentStatus == .pending
                                        }
                                        .sorted {
                                            ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast)
                                        }
                                        .prefix(5)
                                )
                            )
                            jobsSection(
                                title: "Recently Completed",'''
    if marker not in dashboard:
        raise RuntimeError("Could not add Pending Payments dashboard section")
    dashboard = dashboard.replace(marker, section, 1)
dashboard_path.write_text(dashboard, encoding="utf-8")


# MARK: - Remove Job Types management from Settings; types remain addable in New Job.
settings_path = Path("NextJob/Views/SettingsView.swift")
settings = settings_path.read_text(encoding="utf-8")
settings = settings.replace('    @State private var newJobType = ""\n', '')
settings = settings.replace('    @State private var showingAddType = false\n', '')
job_types_start = settings.find('''                    Section {
                        ForEach(store.settings.jobTypes) { type in''')
job_types_end_marker = '''                    Section {
                        Button {
                            createCompleteBackup()'''
job_types_end = settings.find(job_types_end_marker, job_types_start)
if job_types_start >= 0 and job_types_end >= 0:
    settings = settings[:job_types_start] + settings[job_types_end:]
alert_start = settings.find('''            .alert("Add Job Type", isPresented: $showingAddType) {''')
alert_end = settings.find('''            .sheet(isPresented: $showingBackupExporter) {''', alert_start)
if alert_start >= 0 and alert_end >= 0:
    settings = settings[:alert_start] + settings[alert_end:]
settings = settings.replace('LabeledContent("Version", value: "1.0.3")', 'LabeledContent("Version", value: "1.0.4")')
settings = settings.replace('LabeledContent("Version", value: "1.0.2")', 'LabeledContent("Version", value: "1.0.4")')
settings_path.write_text(settings, encoding="utf-8")


# MARK: - Version metadata.
project_path = Path("NextJob/project.yml")
project = project_path.read_text(encoding="utf-8")
project = project.replace('MARKETING_VERSION: "1.0.3"', 'MARKETING_VERSION: "1.0.4"')
project = project.replace('CURRENT_PROJECT_VERSION: "4"', 'CURRENT_PROJECT_VERSION: "5"')
project_path.write_text(project, encoding="utf-8")

print("Next Job 1.0.4 Gmail recovery and payment filters applied.")
