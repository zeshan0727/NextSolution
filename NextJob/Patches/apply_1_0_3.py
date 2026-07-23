from pathlib import Path
import re

# Add the payment and invoice card to the fully migrated job-detail screen.
detail_path = Path("NextJob/Views/JobDetailView.swift")
detail = detail_path.read_text(encoding="utf-8")
if "PaymentInvoiceView(jobID: job.id)" not in detail:
    marker = "                        detailsCard(job)\n                        requestedDocumentsCard(job)"
    replacement = "                        detailsCard(job)\n                        PaymentInvoiceView(jobID: job.id)\n                        requestedDocumentsCard(job)"
    if marker not in detail:
        raise RuntimeError("Could not insert Payment & Invoice card")
    detail = detail.replace(marker, replacement, 1)

# Upgrade the legacy completion email available directly from job details.
completion_pattern = re.compile(
    r'''            let subject = "Completed – \\(updatedJob\.title\)"\n'''
    r'''            let body = """\n.*?\n            """''',
    re.DOTALL,
)
completion_replacement = '''            let subject = "Completion Documents – \\(updatedJob.title)"
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
detail, replaced = completion_pattern.subn(completion_replacement, detail, count=1)
if replaced != 1:
    raise RuntimeError("Could not upgrade the direct completion email")
detail_path.write_text(detail, encoding="utf-8")

# Preserve payment and invoice fields whenever a job is edited.
editor_path = Path("NextJob/Views/JobEditorView.swift")
editor = editor_path.read_text(encoding="utf-8")
editor_marker = '''            emailHistory: original?.emailHistory ?? [],
            createdAt: original?.createdAt ?? Date(),
            updatedAt: Date()
'''
editor_replacement = '''            emailHistory: original?.emailHistory ?? [],
            createdAt: original?.createdAt ?? Date(),
            updatedAt: Date(),
            paymentStatus: original?.paymentStatus,
            paymentReceivedDate: original?.paymentReceivedDate,
            invoiceNumber: original?.invoiceNumber,
            invoiceIssuedDate: original?.invoiceIssuedDate,
            invoiceDueDate: original?.invoiceDueDate
'''
if editor_marker not in editor:
    raise RuntimeError("Could not preserve payment fields in JobEditor")
editor = editor.replace(editor_marker, editor_replacement, 1)
editor_path.write_text(editor, encoding="utf-8")

# Show token usage returned by the Responses API and clear it with each new draft.
ai_path = Path("NextJob/Views/AIEmailView.swift")
ai = ai_path.read_text(encoding="utf-8")
if "@State private var usageText" not in ai:
    ai = ai.replace(
        '    @State private var bodyText = ""\n',
        '    @State private var bodyText = ""\n    @State private var usageText = ""\n',
        1,
    )
    ai = ai.replace(
        '''                TextEditor(text: $bodyText)
                    .frame(minHeight: 210)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Button {
''',
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
    ai = ai.replace(
        '''                subject = result.subject
                bodyText = result.body
''',
        '''                subject = result.subject
                bodyText = result.body
                usageText = "Tokens: input \\(result.inputTokens ?? 0) • output \\(result.outputTokens ?? 0) • total \\(result.totalTokens ?? 0)"
''',
        1,
    )
ai_path.write_text(ai, encoding="utf-8")

# Keep the request compatible with GPT-4.1 presets; verbosity is GPT-5-specific.
openai_path = Path("NextJob/Services/OpenAIEmailService.swift")
openai = openai_path.read_text(encoding="utf-8")
openai = openai.replace('                "verbosity": "low",\n', '')
openai_path.write_text(openai, encoding="utf-8")

# Update the visible app version.
settings_path = Path("NextJob/Views/SettingsView.swift")
settings = settings_path.read_text(encoding="utf-8")
settings = settings.replace('LabeledContent("Version", value: "1.0.2")', 'LabeledContent("Version", value: "1.0.3")')
settings_path.write_text(settings, encoding="utf-8")
