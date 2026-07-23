import SwiftUI

private enum JobFilter: String, CaseIterable, Identifiable {
    case all
    case notStarted
    case inProgress
    case waiting
    case completed
    case overdue

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All Jobs"
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .waiting: return "Waiting"
        case .completed: return "Completed"
        case .overdue: return "Overdue"
        }
    }
}

struct JobsView: View {
    @EnvironmentObject private var store: JobStore
    @State private var searchText = ""
    @State private var filter: JobFilter = .all
    @State private var jobToDelete: JobRecord?

    private var filteredJobs: [JobRecord] {
        store.sortedJobs.filter { job in
            let matchesSearch = searchText.isEmpty || [job.title, job.clientName, job.jobType, job.notes]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .notStarted: matchesFilter = job.status == .notStarted
            case .inProgress: matchesFilter = job.status == .inProgress
            case .waiting: matchesFilter = job.status == .waitingForDocuments
            case .completed: matchesFilter = job.status == .completed
            case .overdue: matchesFilter = job.isOverdue
            }
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if filteredJobs.isEmpty {
                    EmptyStateView(
                        title: store.jobs.isEmpty ? "No jobs yet" : "No matching jobs",
                        message: store.jobs.isEmpty ? "Add a job using the + button." : "Change the search or status filter.",
                        systemImage: "tray"
                    )
                    .padding()
                } else {
                    List {
                        ForEach(filteredJobs) { job in
                            NavigationLink {
                                JobDetailView(jobID: job.id)
                            } label: {
                                JobRow(job: job, currency: store.settings.currency)
                            }
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if job.status == .notStarted {
                                    Button {
                                        store.setStatus(.inProgress, jobID: job.id)
                                    } label: {
                                        Label("Start", systemImage: "play.fill")
                                    }
                                    .tint(.blue)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    jobToDelete = job
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                if job.status != .completed {
                                    Button {
                                        store.complete(jobID: job.id)
                                    } label: {
                                        Label("Complete", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Jobs")
            .searchable(text: $searchText, prompt: "Search jobs, types or notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(JobFilter.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    } label: {
                        Label(filter.title, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .confirmationDialog("Delete this job?", isPresented: Binding(
                get: { jobToDelete != nil },
                set: { if !$0 { jobToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Job and Files", role: .destructive) {
                    if let jobToDelete { store.delete(jobToDelete) }
                    jobToDelete = nil
                }
                Button("Cancel", role: .cancel) { jobToDelete = nil }
            } message: {
                Text("This permanently removes the job and its saved files from the app.")
            }
        }
    }
}
