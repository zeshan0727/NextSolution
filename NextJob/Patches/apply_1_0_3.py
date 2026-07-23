from pathlib import Path

# Add payment and invoice controls to the fully migrated job-detail screen.
detail_path = Path("NextJob/Views/JobDetailView.swift")
detail = detail_path.read_text(encoding="utf-8")
if "PaymentInvoiceView(jobID: job.id)" not in detail:
    marker = "                        detailsCard(job)\n                        requestedDocumentsCard(job)"
    if marker not in detail:
        raise RuntimeError("Could not locate the job-detail card sequence")
    detail = detail.replace(
        marker,
        "                        detailsCard(job)\n                        PaymentInvoiceView(jobID: job.id)\n                        requestedDocumentsCard(job)",
        1,
    )

# Upgrade the completion email available directly inside a job.
if 'let subject = "Completion Documents – \\(updatedJob.title)"' not in detail:
    start_marker = '            let subject = "Completed – \\(updatedJob.title)"\n'
    start = detail.find(start_marker)
    if start < 0:
        raise RuntimeError("Could not locate the legacy completion subject")
    body_start = detail.find('            let body = """\n', start)
    if body_start < 0:
        raise RuntimeError("Could not locate the legacy completion body")
    body_end = detail.find('\n            """', body_start + len('            let body = """\n'))
    if body_end < 0:
        raise RuntimeError("Could not locate the end of the legacy completion body")
    body_end += len('\n            """')
    replacement = '''            let subject = "Completion Documents – \\(updatedJob.title)"
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

            The completion documents and relevant supporting files are included in the attached ZIP package. Please review them and let me know if any clarification or additional work is required.

            Kind regards,
            Zeeshan
            """'''
    detail = detail[:start] + replacement + detail[body_end:]
detail_path.write_text(detail, encoding="utf-8")

# Preserve payment and invoice fields whenever an existing job is edited.
editor_path = Path("NextJob/Views/JobEditorView.swift")
editor = editor_path.read_text(encoding="utf-8")
if "paymentStatus: original?.paymentStatus" not in editor:
    marker = '''            emailHistory: original?.emailHistory ?? [],
            createdAt: original?.createdAt ?? Date(),
            updatedAt: Date()
'''
    if marker not in editor:
        raise RuntimeError("Could not locate the JobEditor record ending")
    editor = editor.replace(
        marker,
        '''            emailHistory: original?.emailHistory ?? [],
            createdAt: original?.createdAt ?? Date(),
            updatedAt: Date(),
            paymentStatus: original?.paymentStatus,
            paymentReceivedDate: original?.paymentReceivedDate,
            invoiceNumber: original?.invoiceNumber,
            invoiceIssuedDate: original?.invoiceIssuedDate,
            invoiceDueDate: original?.invoiceDueDate
''',
        1,
    )
editor_path.write_text(editor, encoding="utf-8")

# Show Responses API token usage beneath a successful AI draft.
ai_path = Path("NextJob/Views/AIEmailView.swift")
ai = ai_path.read_text(encoding="utf-8")
if "@State private var usageText" not in ai:
    state_marker = '    @State private var bodyText = ""\n'
    if state_marker not in ai:
        raise RuntimeError("Could not locate AI body state")
    ai = ai.replace(state_marker, state_marker + '    @State private var usageText = ""\n', 1)

    editor_marker = '''                TextEditor(text: $bodyText)
                    .frame(minHeight: 210)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Button {
'''
    if editor_marker in ai:
        ai = ai.replace(
            editor_marker,
            '''                TextEditor(text: $bodyText)
                    .frame(minHeight: 210)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                if !usageText.isEmpty {
                    Label(usageText, systemImage: "chart.bar.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
''',
            1,
        )

    ai = ai.replace(
        '''            .onChange(of: selectedJobID) { _ in
                subject = ""
                bodyText = ""
            }
''',
        '''            .onChange(of: selectedJobID) { _ in
                subject = ""
                bodyText = ""
                usageText = ""
            }
''',
        1,
    )
    result_marker = '''                subject = result.subject
                bodyText = result.body
'''
    if result_marker not in ai:
        raise RuntimeError("Could not locate AI result assignment")
    ai = ai.replace(
        result_marker,
        '''                subject = result.subject
                bodyText = result.body
                usageText = "Tokens: input \\(result.inputTokens ?? 0) • output \\(result.outputTokens ?? 0) • total \\(result.totalTokens ?? 0)"
''',
        1,
    )
ai_path.write_text(ai, encoding="utf-8")

# The verbosity option is not accepted by every complimentary-token preset.
openai_path = Path("NextJob/Services/OpenAIEmailService.swift")
openai = openai_path.read_text(encoding="utf-8")
openai = openai.replace('                "verbosity": "low",\n', '')
openai_path.write_text(openai, encoding="utf-8")

# Update the visible app version.
settings_path = Path("NextJob/Views/SettingsView.swift")
settings = settings_path.read_text(encoding="utf-8")
settings = settings.replace('LabeledContent("Version", value: "1.0.2")', 'LabeledContent("Version", value: "1.0.3")')
settings_path.write_text(settings, encoding="utf-8")
