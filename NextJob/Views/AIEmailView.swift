import SwiftUI

struct AIEmailView: View {
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var emailDraftStore: EmailDraftStore
    @StateObject private var openAIConfiguration = OpenAIConfigurationStore.shared
    @StateObject private var emailConfiguration = EmailConfigurationStore.shared

    @State private var selectedJobID: UUID?
    @State private var purpose: JobEmailPurpose = .completion
    @State private var tone = "Professional and concise"
    @State private var additionalInstruction = ""
    @State private var subject = ""
    @State private var body = ""
    @State private var isGenerating = false
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showingNotice = false

    private let tones = [
        "Professional and concise",
        "Friendly and professional",
        "Formal",
        "Polite and firm"
    ]

    private var selectedJob: JobRecord? {
        guard let selectedJobID else { return nil }
        return store.job(id: selectedJobID)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if store.jobs.isEmpty {
                    EmptyStateView(
                        title: "No jobs available",
                        message: "Create a job before asking AI to draft an email.",
                        systemImage: "sparkles"
                    )
                    .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            statusCard
                            jobSelectionCard
                            instructionsCard
                            resultCard
                        }
                        .padding()
                        .padding(.bottom, 24)
                    }
                }

                if isGenerating {
                    Color.black.opacity(0.22).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Crafting email from job details…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .navigationTitle("AI Email")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        OpenAISetupView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("OpenAI setup")
                }
            }
            .onAppear {
                selectedJobID = emailDraftStore.selectedJobID ?? store.sortedJobs.first?.id
                if let job = selectedJob {
                    purpose = emailDraftStore.selectedJobID == job.id
                        ? emailDraftStore.purpose
                        : .completion
                }
            }
            .onChange(of: selectedJobID) { _ in
                subject = ""
                body = ""
            }
            .alert(noticeTitle, isPresented: $showingNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(noticeMessage)
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: openAIConfiguration.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(openAIConfiguration.isConfigured ? .green : .orange)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(openAIConfiguration.isConfigured ? "OpenAI email drafting ready" : "OpenAI setup required")
                    .font(.headline)
                Text(openAIConfiguration.isConfigured
                     ? "Model: \(openAIConfiguration.model)"
                     : "Open Settings or tap the gear to add an API key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glassCard()
    }

    private var jobSelectionCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionTitle(title: "Job Context", systemImage: "briefcase.fill")

            Picker("Job", selection: $selectedJobID) {
                ForEach(store.sortedJobs) { job in
                    Text("\(job.title) • \(job.status.title)").tag(Optional(job.id))
                }
            }
            .pickerStyle(.menu)

            Picker("Email purpose", selection: $purpose) {
                ForEach(JobEmailPurpose.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            if let job = selectedJob {
                Divider()
                HStack {
                    StatusBadge(status: job.status, overdue: job.isOverdue)
                    Spacer()
                    Text(job.jobType)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                detailRow("Assigned", job.assignedDate.formatted(date: .abbreviated, time: .shortened))
                detailRow("Due", job.dueDate.formatted(date: .abbreviated, time: .shortened))
                detailRow("Price", "\(store.settings.currency) \(job.price, specifier: "%.2f")")
            }
        }
        .glassCard()
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Draft Instructions", systemImage: "slider.horizontal.3")

            Picker("Tone", selection: $tone) {
                ForEach(tones, id: \.self) { item in
                    Text(item).tag(item)
                }
            }
            .pickerStyle(.menu)

            TextEditor(text: $additionalInstruction)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if additionalInstruction.isEmpty {
                        Text("Optional instruction, such as mention a missing bank statement…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                generate()
            } label: {
                Label("Craft Email with OpenAI", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || selectedJob == nil)
        }
        .glassCard()
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Draft", systemImage: "doc.text.fill")

            if subject.isEmpty && body.isEmpty {
                Text("The generated subject and message will appear here. AI uses the selected job status, dates, notes, requested documents, completion notes, time and price.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Subject", text: $subject)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                TextEditor(text: $body)
                    .frame(minHeight: 210)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Button {
                    useInEmailTab()
                } label: {
                    Label("Use in Email Tab", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .glassCard()
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func generate() {
        guard let job = selectedJob else { return }
        isGenerating = true
        Task {
            defer { isGenerating = false }
            do {
                let result = try await OpenAIEmailService().craft(
                    job: job,
                    purpose: purpose,
                    tone: tone,
                    additionalInstruction: additionalInstruction,
                    configuration: openAIConfiguration,
                    signature: emailConfiguration.configuration.signature
                )
                subject = result.subject
                body = result.body
            } catch {
                showNotice("Email Draft Failed", error.localizedDescription)
            }
        }
    }

    private func useInEmailTab() {
        guard let job = selectedJob,
              !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showNotice("Draft Needed", "Generate or enter an email draft first.")
            return
        }
        emailDraftStore.applyAI(
            draft: OpenAIEmailDraft(subject: subject, body: body),
            jobID: job.id,
            purpose: purpose,
            recipient: store.settings.companyEmail
        )
        showNotice("Added to Email Tab", "Open the Email tab to review, attach the completion package and send.")
    }

    private func showNotice(_ title: String, _ message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }
}
