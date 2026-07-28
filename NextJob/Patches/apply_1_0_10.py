from pathlib import Path


# MARK: - Keep job completion and payment state independent.
models_path = Path("NextJob/Models/JobModels.swift")
models = models_path.read_text(encoding="utf-8")
if "var isUnpaid: Bool" not in models:
    models = models.replace(
        '''    var effectivePaymentStatus: PaymentStatus? {
        paymentStatus ?? (status == .completed && price > 0 ? .pending : nil)
    }
''',
        '''    var effectivePaymentStatus: PaymentStatus? {
        paymentStatus ?? (status == .completed && price > 0 ? .pending : nil)
    }

    /// Payment tracking is independent from workflow status. Any priced job
    /// remains unpaid until it is explicitly marked as received.
    var isUnpaid: Bool {
        price > 0 && paymentStatus != .received
    }
''',
        1,
    )

if "let unpaid: Int" not in models:
    models = models.replace(
        '''    let completed: Int
    let overdue: Int
    let completedValue: Double
    let outstandingValue: Double
''',
        '''    let completed: Int
    let unpaid: Int
    let overdue: Int
    let completedValue: Double
    let outstandingValue: Double
    let unpaidValue: Double
''',
        1,
    )
models_path.write_text(models, encoding="utf-8")


store_path = Path("NextJob/Services/JobStore.swift")
store = store_path.read_text(encoding="utf-8")
store = store.replace(
    '''        var completed = 0
        var overdue = 0
        var completedValue = 0.0
        var outstandingValue = 0.0
''',
    '''        var completed = 0
        var unpaid = 0
        var overdue = 0
        var completedValue = 0.0
        var outstandingValue = 0.0
        var unpaidValue = 0.0
''',
    1,
)
store = store.replace(
    '''            if job.status != .completed { outstandingValue += job.price }
            if job.isOverdue { overdue += 1 }
''',
    '''            if job.status != .completed { outstandingValue += job.price }
            if job.isUnpaid {
                unpaid += 1
                unpaidValue += job.price
            }
            if job.isOverdue { overdue += 1 }
''',
    1,
)
store = store.replace(
    '''            waiting: waiting,
            completed: completed,
            overdue: overdue,
            completedValue: completedValue,
            outstandingValue: outstandingValue,
''',
    '''            waiting: waiting,
            completed: completed,
            unpaid: unpaid,
            overdue: overdue,
            completedValue: completedValue,
            outstandingValue: outstandingValue,
            unpaidValue: unpaidValue,
''',
    1,
)
store = store.replace(
    '''    func save(_ job: JobRecord) {
        var updated = job
        updated.updatedAt = Date()
''',
    '''    func save(_ job: JobRecord) {
        var updated = job
        if updated.status == .completed,
           updated.price > 0,
           updated.paymentStatus == nil {
            updated.paymentStatus = .pending
            updated.paymentReceivedDate = nil
        }
        updated.updatedAt = Date()
''',
    1,
)
store = store.replace(
    '''            if status == .completed {
                job.completedDate = job.completedDate ?? Date()
            } else {
''',
    '''            if status == .completed {
                job.completedDate = job.completedDate ?? Date()
                if job.price > 0, job.paymentStatus == nil {
                    job.paymentStatus = .pending
                    job.paymentReceivedDate = nil
                }
            } else {
''',
    1,
)
store = store.replace(
    '''            job.status = .completed
            job.completedDate = Date()
            if let actualMinutes { job.actualMinutes = actualMinutes }
''',
    '''            job.status = .completed
            job.completedDate = Date()
            if job.price > 0, job.paymentStatus == nil {
                job.paymentStatus = .pending
                job.paymentReceivedDate = nil
            }
            if let actualMinutes { job.actualMinutes = actualMinutes }
''',
    1,
)
store_path.write_text(store, encoding="utf-8")


# MARK: - Jobs tab filter includes every unpaid job, including completed jobs.
jobs_path = Path("NextJob/Views/JobsView.swift")
jobs = jobs_path.read_text(encoding="utf-8")
jobs = jobs.replace('case .pendingPayments: return "Pending Payments"', 'case .pendingPayments: return "Unpaid Jobs"')
jobs = jobs.replace(
    '''            case .pendingPayments:
                matchesFilter = job.status == .completed
                    && job.price > 0
                    && job.effectivePaymentStatus == .pending
''',
    '''            case .pendingPayments:
                matchesFilter = job.isUnpaid
''',
    1,
)
jobs_path.write_text(jobs, encoding="utf-8")


# MARK: - Tappable dashboard cards and a dedicated Unpaid card/list.
dashboard_path = Path("NextJob/Views/DashboardView.swift")
dashboard_path.write_text(r'''import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: JobStore
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        let summary = store.summary
        let sortedJobs = store.sortedJobs
        let notStartedJobs = sortedJobs.filter { $0.status == .notStarted }
        let inProgressJobs = sortedJobs.filter { $0.status == .inProgress }
        let waitingJobs = sortedJobs.filter { $0.status == .waitingForDocuments }
        let completedJobs = store.jobs
            .filter { $0.status == .completed }
            .sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
        let unpaidJobs = store.jobs
            .filter(\.isUnpaid)
            .sorted {
                if $0.status == .completed, $1.status != .completed { return true }
                if $0.status != .completed, $1.status == .completed { return false }
                return $0.dueDate < $1.dueDate
            }
        let overdueJobs = sortedJobs.filter(\.isOverdue)
        let needsAttention = Array(sortedJobs.lazy.filter { $0.isOverdue || $0.status == .waitingForDocuments }.prefix(5))
        let upcomingJobs = Array(sortedJobs.lazy.filter { $0.status != .completed && !$0.isOverdue }.prefix(5))

        return NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        BrandHeader(subtitle: store.settings.companyName)

                        LazyVGrid(columns: columns, spacing: 12) {
                            metricLink(title: "Not started", value: summary.notStarted, systemImage: "circle", tint: .secondary, jobs: notStartedJobs)
                            metricLink(title: "In progress", value: summary.inProgress, systemImage: "clock.arrow.circlepath", tint: .blue, jobs: inProgressJobs)
                            metricLink(title: "Waiting", value: summary.waiting, systemImage: "doc.badge.ellipsis", tint: .orange, jobs: waitingJobs)
                            metricLink(title: "Completed", value: summary.completed, systemImage: "checkmark.circle.fill", tint: .green, jobs: completedJobs)
                            metricLink(title: "Unpaid", value: summary.unpaid, systemImage: "banknote.fill", tint: .orange, jobs: unpaidJobs)
                            metricLink(title: "Overdue", value: summary.overdue, systemImage: "exclamationmark.triangle.fill", tint: .red, jobs: overdueJobs)
                        }

                        financialSummary(summary, completedJobs: completedJobs, unpaidJobs: unpaidJobs)
                        workloadSummary(summary, jobs: sortedJobs)

                        if store.jobs.isEmpty {
                            EmptyStateView(
                                title: "No jobs recorded yet",
                                message: "Tap the + button to add your first accounting job from KB Accountants.",
                                systemImage: "briefcase"
                            )
                        } else {
                            jobsSection(title: "Needs Attention", systemImage: "exclamationmark.triangle.fill", jobs: needsAttention)
                            jobsSection(title: "Upcoming Jobs", systemImage: "calendar.badge.clock", jobs: upcomingJobs)
                            jobsSection(title: "Unpaid Jobs", systemImage: "banknote.fill", jobs: Array(unpaidJobs.prefix(5)))
                            jobsSection(title: "Recently Completed", systemImage: "checkmark.seal.fill", jobs: Array(completedJobs.prefix(4)))
                        }
                    }
                    .padding()
                    .padding(.bottom, 84)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func metricLink(title: String, value: Int, systemImage: String, tint: Color, jobs: [JobRecord]) -> some View {
        NavigationLink {
            DashboardJobsListView(title: title, jobs: jobs)
        } label: {
            MetricCard(title: title, value: "\(value)", systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens all \(title.lowercased()) jobs")
    }

    private func financialSummary(_ summary: DashboardSummary, completedJobs: [JobRecord], unpaidJobs: [JobRecord]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Job Value", systemImage: "banknote.fill")
            HStack {
                valueLink(title: "Completed", value: summary.completedValue, tint: .green, jobs: completedJobs)
                Divider().frame(height: 54)
                valueLink(title: "Pending Balance", value: summary.unpaidValue, tint: .orange, jobs: unpaidJobs)
            }
        }
        .glassCard()
    }

    private func workloadSummary(_ summary: DashboardSummary, jobs: [JobRecord]) -> some View {
        NavigationLink {
            DashboardJobsListView(title: "All Jobs", jobs: jobs)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Time Summary", systemImage: "timer")
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Targeted").font(.caption).foregroundStyle(.secondary)
                        Text(JobRecord.timeText(minutes: summary.targetMinutes)).font(.title3.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Recorded").font(.caption).foregroundStyle(.secondary)
                        Text(JobRecord.timeText(minutes: summary.actualMinutes)).font(.title3.bold())
                    }
                }
                ProgressView(value: Double(summary.actualMinutes), total: Double(max(summary.targetMinutes, 1)))
                    .tint(.blue)
            }
            .glassCard()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens all jobs")
    }

    private func valueLink(title: String, value: Double, tint: Color, jobs: [JobRecord]) -> some View {
        NavigationLink {
            DashboardJobsListView(title: title == "Pending Balance" ? "Unpaid Jobs" : "Completed Jobs", jobs: jobs)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text("\(store.settings.currency) \(value, specifier: "%.2f")")
                        .font(.title3.bold())
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens related jobs")
    }

    @ViewBuilder
    private func jobsSection(title: String, systemImage: String, jobs: [JobRecord]) -> some View {
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink {
                    DashboardJobsListView(title: title, jobs: jobs)
                } label: {
                    HStack {
                        SectionTitle(title: title, systemImage: systemImage)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                ForEach(jobs) { job in
                    NavigationLink {
                        JobDetailView(jobID: job.id)
                    } label: {
                        JobRow(job: job, currency: store.settings.currency)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(uiColor: .secondarySystemBackground).opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .glassCard()
        }
    }
}

private struct DashboardJobsListView: View {
    @EnvironmentObject private var store: JobStore
    let title: String
    let jobs: [JobRecord]

    var body: some View {
        ZStack {
            AppBackground()
            if jobs.isEmpty {
                EmptyStateView(
                    title: "No \(title.lowercased())",
                    message: "Jobs matching this dashboard card will appear here.",
                    systemImage: "tray"
                )
                .padding()
            } else {
                List {
                    ForEach(jobs) { job in
                        NavigationLink {
                            JobDetailView(jobID: job.id)
                        } label: {
                            JobRow(job: job, currency: store.settings.currency)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
                .transaction { transaction in transaction.animation = nil }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
''', encoding="utf-8")


# MARK: - Version metadata.
settings_path = Path("NextJob/Views/SettingsView.swift")
settings = settings_path.read_text(encoding="utf-8")
settings = settings.replace('LabeledContent("Version", value: "1.0.9")', 'LabeledContent("Version", value: "1.0.10")')
settings_path.write_text(settings, encoding="utf-8")

project_path = Path("NextJob/project.yml")
project = project_path.read_text(encoding="utf-8")
project = project.replace('MARKETING_VERSION: "1.0.9"', 'MARKETING_VERSION: "1.0.10"')
project = project.replace('CURRENT_PROJECT_VERSION: "10"', 'CURRENT_PROJECT_VERSION: "11"')
project_path.write_text(project, encoding="utf-8")

email_path = Path("NextJob/Services/EmailDeliveryService.swift")
email = email_path.read_text(encoding="utf-8")
email = email.replace("NextJob-iOS/1.0.9", "NextJob-iOS/1.0.10")
email_path.write_text(email, encoding="utf-8")

print("Next Job 1.0.10 unpaid tracking and dashboard navigation applied.")
