import SwiftUI

private struct JobDraft {
    var id: UUID?
    var title = ""
    var clientName = ""
    var jobType = ""
    var assignedDate = Date()
    var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    var status: JobStatus = .notStarted
    var targetMinutes = 60
    var actualMinutes = 0
    var hasActualTime = false
    var price = 0.0
    var notes = ""
    var requestedDocuments = ""
    var completionNotes = ""
    var original: JobRecord?

    init(job: JobRecord? = nil) {
        guard let job else { return }
        id = job.id
        title = job.title
        clientName = job.clientName
        jobType = job.jobType
        assignedDate = job.assignedDate
        dueDate = job.dueDate
        status = job.status
        targetMinutes = job.targetMinutes
        actualMinutes = job.actualMinutes ?? 0
        hasActualTime = job.actualMinutes != nil
        price = job.price
        notes = job.notes
        requestedDocuments = job.requestedDocuments
        completionNotes = job.completionNotes
        original = job
    }

    func makeRecord() -> JobRecord {
        JobRecord(
            id: id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            clientName: clientName.trimmingCharacters(in: .whitespacesAndNewlines),
            jobType: jobType,
            assignedDate: assignedDate,
            dueDate: dueDate,
            completedDate: status == .completed ? (original?.completedDate ?? Date()) : nil,
            status: status,
            targetMinutes: max(0, targetMinutes),
            actualMinutes: hasActualTime ? max(0, actualMinutes) : nil,
            price: max(0, price),
            notes: notes,
            requestedDocuments: requestedDocuments,
            completionNotes: completionNotes,
            attachments: original?.attachments ?? [],
            emailHistory: original?.emailHistory ?? [],
            createdAt: original?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }
}

struct JobEditorView: View {
    @EnvironmentObject private var store: JobStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: JobDraft
    @State private var showValidation = false
    @State private var newJobType = ""
    @State private var showingNewTypeFields = false
    private let isEditing: Bool

    init(job: JobRecord? = nil) {
        _draft = State(initialValue: JobDraft(job: job))
        isEditing = job != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job Details") {
                    TextField("Job name", text: $draft.title)
                    TextField("Company", text: $draft.clientName)

                    Picker("Job type", selection: $draft.jobType) {
                        ForEach(store.settings.jobTypes) { type in
                            Text(type.name).tag(type.name)
                        }
                    }

                    DisclosureGroup("Job type not in the list?", isExpanded: $showingNewTypeFields) {
                        TextField("New job type", text: $newJobType)
                            .textInputAutocapitalization(.words)
                        Button {
                            addNewJobType()
                        } label: {
                            Label("Add and Select Job Type", systemImage: "plus.circle.fill")
                        }
                        .disabled(newJobType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Picker("Status", selection: $draft.status) {
                        ForEach(JobStatus.allCases) { status in
                            Label(status.title, systemImage: status.systemImage).tag(status)
                        }
                    }
                }

                Section("Dates") {
                    DatePicker(
                        "Assigned",
                        selection: $draft.assignedDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "Due",
                        selection: $draft.dueDate,
                        in: draft.assignedDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Time & Price") {
                    Stepper(value: $draft.targetMinutes, in: 0...100_000, step: 15) {
                        LabeledContent(
                            "Target time",
                            value: JobRecord.timeText(minutes: draft.targetMinutes)
                        )
                    }
                    Toggle("Record actual time", isOn: $draft.hasActualTime)
                    if draft.hasActualTime {
                        Stepper(value: $draft.actualMinutes, in: 0...100_000, step: 15) {
                            LabeledContent(
                                "Actual time",
                                value: JobRecord.timeText(minutes: draft.actualMinutes)
                            )
                        }
                    }
                    TextField(
                        "Job price",
                        value: $draft.price,
                        format: .number.precision(.fractionLength(2))
                    )
                    .keyboardType(.decimalPad)
                }

                Section("Documents to Request") {
                    TextEditor(text: $draft.requestedDocuments).frame(minHeight: 90)
                    Text("This list is inserted into the document-request email.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Job Notes") {
                    TextEditor(text: $draft.notes).frame(minHeight: 100)
                }

                Section("Completion Notes") {
                    TextEditor(text: $draft.completionNotes).frame(minHeight: 100)
                }
            }
            .navigationTitle(isEditing ? "Edit Job" : "New Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                if draft.clientName.isEmpty {
                    draft.clientName = store.settings.companyName
                }
                if draft.jobType.isEmpty {
                    draft.jobType = store.settings.jobTypes.first?.name ?? "Other"
                }
            }
            .alert("Job name required", isPresented: $showValidation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enter a clear name before saving this job.")
            }
        }
    }

    private func addNewJobType() {
        let trimmed = newJobType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addJobType(named: trimmed)
        draft.jobType = store.settings.jobTypes.first(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        })?.name ?? trimmed
        newJobType = ""
        showingNewTypeFields = false
    }

    private func save() {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showValidation = true
            return
        }
        store.save(draft.makeRecord())
        dismiss()
    }
}
