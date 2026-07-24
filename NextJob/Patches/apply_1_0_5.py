from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Could not locate {label} in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# MARK: - Automatic Gmail from Job Details with confirmation and acceptance notice.
detail_path = Path("NextJob/Views/JobDetailView.swift")
detail = detail_path.read_text(encoding="utf-8")

if "struct JobDetailAutoEmailDraft" not in detail:
    marker = "import MessageUI\n\nstruct JobDetailView: View {"
    replacement = '''import MessageUI

private struct JobDetailAutoEmailDraft: Identifiable {
    let id = UUID()
    let jobID: UUID
    let recipient: String
    let subject: String
    let body: String
    let kind: JobEmailRecord.Kind
    let attachCompletionPackage: Bool
}

struct JobDetailView: View {'''
    if marker not in detail:
        raise RuntimeError("Could not insert automatic email draft model")
    detail = detail.replace(marker, replacement, 1)

if "@StateObject private var emailConfiguration" not in detail:
    detail = detail.replace(
        "    @EnvironmentObject private var store: JobStore\n",
        "    @EnvironmentObject private var store: JobStore\n    @StateObject private var emailConfiguration = EmailConfigurationStore.shared\n",
        1,
    )

if "@State private var pendingAutoEmail" not in detail:
    detail = detail.replace(
        '    @State private var showingCompletionSheet = false\n',
        '''    @State private var showingCompletionSheet = false
    @State private var pendingAutoEmail: JobDetailAutoEmailDraft?
    @State private var isSendingAutoEmail = false
    @State private var autoEmailProgressMessage = "Sending email through Gmail…"
''',
        1,
    )

old_overlay = '''            if isImportingItems {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(importMessage)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(32)
            }'''
new_overlay = '''            if isImportingItems || isSendingAutoEmail {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(isSendingAutoEmail ? autoEmailProgressMessage : importMessage)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(32)
            }'''
if old_overlay not in detail:
    raise RuntimeError("Could not update Job Details progress overlay")
detail = detail.replace(old_overlay, new_overlay, 1)

if 'confirmationDialog("Send Automatically with Gmail?"' not in detail:
    marker = '''        .sheet(isPresented: $showingCompletionSheet) {
            completionSheet
        }
        .alert(noticeTitle, isPresented: $showingNotice) {'''
    replacement = '''        .sheet(isPresented: $showingCompletionSheet) {
            completionSheet
        }
        .confirmationDialog(
            "Send Automatically with Gmail?",
            isPresented: Binding(
                get: { pendingAutoEmail != nil },
                set: { if !$0 { pendingAutoEmail = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingAutoEmail
        ) { draft in
            Button("Send Now") {
                pendingAutoEmail = nil
                sendAutomaticEmail(draft)
            }
            Button("Cancel", role: .cancel) {
                pendingAutoEmail = nil
            }
        } message: { draft in
            Text(
                "To: \\(draft.recipient)\\nSubject: \\(draft.subject)\\n"
                    + (draft.attachCompletionPackage
                       ? "The completion ZIP package will be attached."
                       : "This email has no attachment.")
            )
        }
        .alert(noticeTitle, isPresented: $showingNotice) {'''
    if marker not in detail:
        raise RuntimeError("Could not add Gmail confirmation popup")
    detail = detail.replace(marker, replacement, 1)

email_panel_start = detail.find("    private func emailPanel(_ job: JobRecord) -> some View {")
email_panel_end = detail.find("\n    private func historyCard", email_panel_start)
if email_panel_start < 0 or email_panel_end < 0:
    raise RuntimeError("Could not locate Email & Package panel")
new_email_panel = '''    private func emailPanel(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Email & Package", systemImage: "envelope.fill")

            Label(
                emailConfiguration.isGmailConnected
                    ? "Automatic Gmail ready: \\(emailConfiguration.configuration.connectedEmail)"
                    : "Connect Gmail in Settings to send automatically",
                systemImage: emailConfiguration.isGmailConnected
                    ? "checkmark.shield.fill"
                    : "exclamationmark.triangle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(emailConfiguration.isGmailConnected ? .green : .orange)

            Button {
                requestDocuments(job)
            } label: {
                Label("Request Documents", systemImage: "envelope.badge").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isSendingAutoEmail)

            Button {
                completeAndEmail(job)
            } label: {
                Label("Create ZIP & Email Completion", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSendingAutoEmail)

            Button {
                shareZip(job)
            } label: {
                Label("Create & Share Job ZIP", systemImage: "doc.zipper").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isSendingAutoEmail)

            Text("Request and completion emails are sent automatically through Gmail after a confirmation popup. A success notification appears only after the scheduler accepts the email.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }
'''
detail = detail[:email_panel_start] + new_email_panel + detail[email_panel_end:]

request_start = detail.find("    private func requestDocuments(_ job: JobRecord) {")
complete_start = detail.find("\n    private func completeAndEmail", request_start)
share_start = detail.find("\n    private func shareZip", complete_start)
if request_start < 0 or complete_start < 0 or share_start < 0:
    raise RuntimeError("Could not locate Job Details email functions")
new_email_functions = '''    private func requestDocuments(_ job: JobRecord) {
        guard ensureAutomaticGmailReady() else { return }
        guard let recipient = configuredRecipient() else { return }
        let subject = "Documents Required – \\(job.title)"
        let requested = job.requestedDocuments.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = requested.isEmpty
            ? "Please send the documents and information required to complete this job."
            : requested
        let body = """
        Dear Team,

        I am currently working on the following assignment:

        Job: \\(job.title)
        Job type: \\(job.jobType)

        Please provide the following documents or information:
        \\(list)

        Target completion date: \\(job.dueDate.formatted(date: .long, time: .shortened))

        Please let me know if any clarification is required.

        Kind regards,
        Zeeshan
        """
        pendingAutoEmail = JobDetailAutoEmailDraft(
            jobID: job.id,
            recipient: recipient,
            subject: subject,
            body: body,
            kind: .documentRequest,
            attachCompletionPackage: false
        )
    }

    private func completeAndEmail(_ job: JobRecord) {
        guard ensureAutomaticGmailReady() else { return }
        guard let recipient = configuredRecipient() else { return }
        if job.status != .completed {
            store.complete(jobID: job.id, actualMinutes: job.actualMinutes ?? job.targetMinutes)
        }
        let updatedJob = store.job(id: job.id) ?? job
        let subject = "Completion Documents – \\(updatedJob.title)"
        let recordedCompletion = (updatedJob.completedDate ?? Date()).formatted(date: .long, time: .shortened)
        let recordedNotes = updatedJob.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let recordedCompletionNotes = updatedJob.completionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = """
        Dear Team,

        I am pleased to confirm that the following assignment has been completed:

        Job: \\(updatedJob.title)
        Job type: \\(updatedJob.jobType)
        Completion date and time: \\(recordedCompletion)
        Actual time recorded: \\(updatedJob.actualTimeText)

        Job notes:
        \\(recordedNotes.isEmpty ? "No additional job notes were recorded." : recordedNotes)

        Completion notes:
        \\(recordedCompletionNotes.isEmpty ? "No additional completion notes were recorded." : recordedCompletionNotes)

        The completion documents and relevant supporting files will be included in the attached ZIP package. Please review them and let me know if any clarification or additional work is required.

        Kind regards,
        Zeeshan
        """
        pendingAutoEmail = JobDetailAutoEmailDraft(
            jobID: updatedJob.id,
            recipient: recipient,
            subject: subject,
            body: body,
            kind: .completion,
            attachCompletionPackage: true
        )
    }

    private func ensureAutomaticGmailReady() -> Bool {
        guard emailConfiguration.isGmailConnected else {
            showNotice(
                "Gmail Connection Required",
                "Open Settings → Email & Gmail Setup and connect Gmail before using automatic email from Job Details."
            )
            return false
        }
        return true
    }

    private func sendAutomaticEmail(_ draft: JobDetailAutoEmailDraft) {
        guard !isSendingAutoEmail else { return }
        guard let currentJob = store.job(id: draft.jobID) else {
            showNotice("Job Not Found", "The job is no longer available.")
            return
        }

        isSendingAutoEmail = true
        autoEmailProgressMessage = draft.attachCompletionPackage
            ? "Creating the completion ZIP and sending through Gmail…"
            : "Sending the email automatically through Gmail…"

        Task {
            defer { isSendingAutoEmail = false }
            do {
                var attachments: [DirectEmailAttachment] = []
                if draft.attachCompletionPackage {
                    let currency = store.settings.currency
                    let package = try await Task.detached(priority: .userInitiated) {
                        try JobFileService.shared.createJobZip(job: currentJob, currency: currency)
                    }.value
                    attachments.append(
                        DirectEmailAttachment(
                            fileName: package.lastPathComponent,
                            mimeType: "application/zip",
                            data: try Data(contentsOf: package, options: .mappedIfSafe)
                        )
                    )
                }

                let schedulerMessage = try await DirectEmailService().send(
                    recipient: draft.recipient,
                    subject: draft.subject,
                    body: draft.body,
                    attachments: attachments,
                    using: emailConfiguration
                )

                store.addEmailRecord(
                    JobEmailRecord(
                        kind: draft.kind,
                        recipient: draft.recipient,
                        subject: draft.subject
                    ),
                    to: draft.jobID
                )
                showNotice(
                    "Email Accepted",
                    "The scheduler accepted the email for \\(draft.recipient).\\n\\n\\(schedulerMessage)"
                )
            } catch DirectEmailError.connectorExpired {
                showNotice(
                    "Reconnect Gmail",
                    DirectEmailError.connectorExpired.localizedDescription
                )
            } catch {
                showNotice("Email Not Sent", error.localizedDescription)
            }
        }
    }
'''
detail = detail[:request_start] + new_email_functions + detail[share_start:]
detail_path.write_text(detail, encoding="utf-8")


# MARK: - Version metadata and user agent.
email_path = Path("NextJob/Services/EmailDeliveryService.swift")
email = email_path.read_text(encoding="utf-8")
email = email.replace("NextJob-iOS/1.0.4", "NextJob-iOS/1.0.5")
email_path.write_text(email, encoding="utf-8")

settings_path = Path("NextJob/Views/SettingsView.swift")
settings = settings_path.read_text(encoding="utf-8")
settings = settings.replace('LabeledContent("Version", value: "1.0.4")', 'LabeledContent("Version", value: "1.0.5")')
settings_path.write_text(settings, encoding="utf-8")

project_path = Path("NextJob/project.yml")
project = project_path.read_text(encoding="utf-8")
project = project.replace('MARKETING_VERSION: "1.0.4"', 'MARKETING_VERSION: "1.0.5"')
project = project.replace('CURRENT_PROJECT_VERSION: "5"', 'CURRENT_PROJECT_VERSION: "6"')
project_path.write_text(project, encoding="utf-8")

print("Next Job 1.0.5 automatic Job Details Gmail sending applied.")
