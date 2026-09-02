import SwiftUI

struct EmployeeRootView: View {
    @EnvironmentObject private var store: EmployeeVisitStore
    @State private var searchText = ""
    @State private var pendingAssignment: EmployeeVisitAssignment?
    @State private var showingCompletionConfirmation = false
    @State private var showingError = false

    private var filteredAssignments: [EmployeeVisitAssignment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.assignments }
        return store.assignments.filter {
            $0.villaTitle.localizedCaseInsensitiveContains(query) ||
            $0.areaTitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        TabView {
            NavigationStack {
                Group {
                    if store.assignments.isEmpty && store.isRefreshing {
                        ProgressView("Loading visits…")
                    } else if filteredAssignments.isEmpty {
                        EmployeeEmptyState(
                            title: searchText.isEmpty ? "No Assigned Villas" : "No Results",
                            message: searchText.isEmpty ? "The administrator has not synced any active maintenance villas yet." : "Try another villa number or area."
                        )
                    } else {
                        List {
                            Section {
                                HStack {
                                    Label("\(store.assignments.count) villas", systemImage: "house.fill")
                                    Spacer()
                                    if store.isRefreshing { ProgressView().controlSize(.small) }
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }

                            ForEach(filteredAssignments) { assignment in
                                EmployeeVisitCard(assignment: assignment) {
                                    pendingAssignment = assignment
                                    showingCompletionConfirmation = true
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { await store.refresh() }
                    }
                }
                .navigationTitle("Maintenance Visits")
                .searchable(text: $searchText, prompt: "Villa number or area")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task { await store.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(store.isRefreshing)
                    }
                }
            }
            .tabItem { Label("Visits", systemImage: "checkmark.circle.fill") }

            EmployeeSettingsView()
                .tabItem { Label("Settings", systemImage: "person.crop.circle") }
        }
        .tint(.green)
        .confirmationDialog(
            "Mark this visit completed?",
            isPresented: $showingCompletionConfirmation,
            titleVisibility: .visible,
            presenting: pendingAssignment
        ) { assignment in
            Button("Mark Visit Done") {
                Task {
                    let success = await store.markDone(assignment)
                    if !success, store.lastError != nil { showingError = true }
                    pendingAssignment = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingAssignment = nil }
        } message: { assignment in
            Text("\(assignment.villaTitle) • \(assignment.areaTitle)\nThe completion will sync automatically to Aspire Maintenance.")
        }
        .onChange(of: store.lastError) { value in
            if value != nil { showingError = true }
        }
        .alert("Visit Sync", isPresented: $showingError) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "Unable to sync visits.")
        }
    }
}

struct EmployeeEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "house.and.flag")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct EmployeeVisitCard: View {
    @EnvironmentObject private var store: EmployeeVisitStore
    let assignment: EmployeeVisitAssignment
    let markDone: () -> Void

    private var completed: Int { store.completedCount(for: assignment.id) }
    private var planned: Int { max(0, assignment.plannedVisits) }
    private var remaining: Int { max(0, planned - completed) }
    private var isComplete: Bool { planned > 0 && completed >= planned }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "house.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .frame(width: 42, height: 42)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(assignment.villaTitle)
                        .font(.headline)
                    Label(assignment.areaTitle, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(isComplete ? "DONE" : "\(remaining) LEFT")
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((isComplete ? Color.green : Color.orange).opacity(0.12), in: Capsule())
                    .foregroundStyle(isComplete ? Color.green : Color.orange)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Visits this month")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(completed) / \(planned)")
                        .font(.subheadline.bold())
                }
                ProgressView(value: Double(min(completed, max(planned, 1))), total: Double(max(planned, 1)))
                    .tint(isComplete ? .green : .orange)
            }

            let recent = store.recentCompletions(for: assignment.id, limit: 1)
            if let latest = recent.first {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Last visit: \(DateFormatter.employeeVisitDate.string(from: latest.completedAt))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(action: markDone) {
                Label(isComplete ? "Monthly Visits Complete" : "Mark Visit Done", systemImage: isComplete ? "checkmark.seal.fill" : "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isComplete || planned == 0)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .padding(.vertical, 4)
    }
}

struct EmployeeSettingsView: View {
    @EnvironmentObject private var store: EmployeeVisitStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Employee") {
                    TextField("Your name", text: $store.employeeName)
                        .textInputAutocapitalization(.words)
                    Text("Your name is attached only to visit completion records so the administrator can see who completed a visit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("What you can see") {
                    Label("Villa number", systemImage: "house")
                    Label("Area", systemImage: "mappin.and.ellipse")
                    Label("Monthly visit count", systemImage: "number.circle")
                    Label("Visit completion history", systemImage: "checkmark.circle")
                }

                Section("Privacy") {
                    Text("Customer names, phone numbers, email addresses, payment details, invoices, rates, private notes and full customer records are not downloaded to this app.")
                        .font(.subheadline)
                }

                Section {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if store.isRefreshing { ProgressView() }
                        }
                    }
                    .disabled(store.isRefreshing)
                }
            }
            .navigationTitle("Employee")
        }
    }
}
