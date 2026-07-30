import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: JobStore
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        BrandHeader(subtitle: store.settings.companyName)

                        LazyVGrid(columns: columns, spacing: 12) {
                            MetricCard(title: "Not started", value: "\(store.summary.notStarted)", systemImage: "circle", tint: .secondary)
                            MetricCard(title: "In progress", value: "\(store.summary.inProgress)", systemImage: "clock.arrow.circlepath", tint: .blue)
                            MetricCard(title: "Waiting", value: "\(store.summary.waiting)", systemImage: "doc.badge.ellipsis", tint: .orange)
                            MetricCard(title: "Completed", value: "\(store.summary.completed)", systemImage: "checkmark.circle.fill", tint: .green)
                        }

                        financialSummary
                        workloadSummary

                        if store.jobs.isEmpty {
                            EmptyStateView(
                                title: "No jobs recorded yet",
                                message: "Tap the + button to add your first accounting job from KB Accountants.",
                                systemImage: "briefcase"
                            )
                        } else {
                            jobsSection(
                                title: "Needs Attention",
                                systemImage: "exclamationmark.triangle.fill",
                                jobs: Array(store.sortedJobs.filter { $0.isOverdue || $0.status == .waitingForDocuments }.prefix(5))
                            )
                            jobsSection(
                                title: "Upcoming Jobs",
                                systemImage: "calendar.badge.clock",
                                jobs: Array(store.sortedJobs.filter { $0.status != .completed && !$0.isOverdue }.prefix(5))
                            )
                            jobsSection(
                                title: "Recently Completed",
                                systemImage: "checkmark.seal.fill",
                                jobs: Array(store.jobs.filter { $0.status == .completed }.sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }.prefix(4))
                            )
                        }
                    }
                    .padding()
                    .padding(.bottom, 84)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var financialSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Job Value", systemImage: "banknote.fill")
            HStack {
                valueColumn(title: "Completed", value: store.summary.completedValue, tint: .green)
                Divider().frame(height: 46)
                valueColumn(title: "Outstanding", value: store.summary.outstandingValue, tint: .orange)
            }
        }
        .glassCard()
    }

    private var workloadSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Time Summary", systemImage: "timer")
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Targeted").font(.caption).foregroundStyle(.secondary)
                    Text(JobRecord.timeText(minutes: store.summary.targetMinutes)).font(.title3.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Recorded").font(.caption).foregroundStyle(.secondary)
                    Text(JobRecord.timeText(minutes: store.summary.actualMinutes)).font(.title3.bold())
                }
            }
            ProgressView(value: Double(store.summary.actualMinutes), total: Double(max(store.summary.targetMinutes, 1)))
                .tint(.blue)
        }
        .glassCard()
    }

    private func valueColumn(title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(store.settings.currency) \(value, specifier: "%.2f")")
                .font(.title3.bold())
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func jobsSection(title: String, systemImage: String, jobs: [JobRecord]) -> some View {
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: title, systemImage: systemImage)
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
