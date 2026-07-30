from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Could not locate {label} in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# MARK: - Reduce GPU-heavy blur and shadow work throughout scrolling screens.
components_path = Path("NextJob/Views/Components.swift")
components = components_path.read_text(encoding="utf-8")
components = components.replace(
    '''            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)''',
    '''            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 5, y: 2)'''
)
components_path.write_text(components, encoding="utf-8")


# MARK: - Compute dashboard collections and totals once per body evaluation.
dashboard_path = Path("NextJob/Views/DashboardView.swift")
dashboard = dashboard_path.read_text(encoding="utf-8")
dashboard = dashboard.replace(
    '''    var body: some View {
        NavigationStack {''',
    '''    var body: some View {
        let summary = store.summary
        let sortedJobs = store.sortedJobs
        let needsAttention = Array(sortedJobs.lazy.filter { $0.isOverdue || $0.status == .waitingForDocuments }.prefix(5))
        let upcomingJobs = Array(sortedJobs.lazy.filter { $0.status != .completed && !$0.isOverdue }.prefix(5))
        let recentlyCompleted = Array(
            store.jobs.lazy
                .filter { $0.status == .completed }
                .sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
                .prefix(4)
        )

        return NavigationStack {''',
    1,
)
dashboard = dashboard.replace('store.summary.notStarted', 'summary.notStarted')
dashboard = dashboard.replace('store.summary.inProgress', 'summary.inProgress')
dashboard = dashboard.replace('store.summary.waiting', 'summary.waiting')
dashboard = dashboard.replace('store.summary.completed', 'summary.completed')
dashboard = dashboard.replace('Array(store.sortedJobs.filter { $0.isOverdue || $0.status == .waitingForDocuments }.prefix(5))', 'needsAttention')
dashboard = dashboard.replace('Array(store.sortedJobs.filter { $0.status != .completed && !$0.isOverdue }.prefix(5))', 'upcomingJobs')
dashboard = dashboard.replace('Array(store.jobs.filter { $0.status == .completed }.sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }.prefix(4))', 'recentlyCompleted')
dashboard = dashboard.replace('financialSummary', 'financialSummary(summary)', 1)
dashboard = dashboard.replace('workloadSummary', 'workloadSummary(summary)', 1)
dashboard = dashboard.replace('    private var financialSummary: some View {', '    private func financialSummary(_ summary: DashboardSummary) -> some View {')
dashboard = dashboard.replace('store.summary.completedValue', 'summary.completedValue')
dashboard = dashboard.replace('store.summary.outstandingValue', 'summary.outstandingValue')
dashboard = dashboard.replace('    private var workloadSummary: some View {', '    private func workloadSummary(_ summary: DashboardSummary) -> some View {')
dashboard = dashboard.replace('store.summary.targetMinutes', 'summary.targetMinutes')
dashboard = dashboard.replace('store.summary.actualMinutes', 'summary.actualMinutes')
dashboard_path.write_text(dashboard, encoding="utf-8")


# MARK: - Avoid rebuilding a joined search string for every job and disable list animations.
jobs_path = Path("NextJob/Views/JobsView.swift")
jobs = jobs_path.read_text(encoding="utf-8")
jobs = jobs.replace(
    '''    private var filteredJobs: [JobRecord] {
        store.sortedJobs.filter { job in
            let matchesSearch = searchText.isEmpty || [job.title, job.clientName, job.jobType, job.notes]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)''',
    '''    private var filteredJobs: [JobRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.sortedJobs.filter { job in
            let matchesSearch = query.isEmpty
                || job.title.localizedCaseInsensitiveContains(query)
                || job.clientName.localizedCaseInsensitiveContains(query)
                || job.jobType.localizedCaseInsensitiveContains(query)
                || job.notes.localizedCaseInsensitiveContains(query)'''
)
jobs = jobs.replace(
    '''                    .scrollContentBackground(.hidden)''',
    '''                    .scrollContentBackground(.hidden)
                    .transaction { transaction in
                        transaction.animation = nil
                    }'''
)
jobs_path.write_text(jobs, encoding="utf-8")


# MARK: - Make Secure Logins scrolling cheaper while retaining the same design.
vault_path = Path("NextJob/Vault/VaultViews.swift")
vault = vault_path.read_text(encoding="utf-8")
vault = vault.replace(
    '.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))',
    '.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))'
)
vault = vault.replace(
    '''                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Logins")''',
    '''                    .padding(.bottom, 24)
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .navigationTitle("Logins")''',
    1,
)
vault_path.write_text(vault, encoding="utf-8")


# MARK: - Prevent unnecessary implicit animation across tab changes and large updates.
root_path = Path("NextJob/Views/AppRootView.swift")
root = root_path.read_text(encoding="utf-8")
root = root.replace(
    '''            TabView(selection: $selectedTab) {''',
    '''            TabView(selection: $selectedTab) {''',
    1,
)
root = root.replace(
    '''            }

            if selectedTab <= 1 {''',
    '''            }
            .transaction { transaction in
                transaction.animation = nil
            }

            if selectedTab <= 1 {''',
    1,
)
root_path.write_text(root, encoding="utf-8")


# MARK: - Version metadata.
settings_path = Path("NextJob/Views/SettingsView.swift")
settings = settings_path.read_text(encoding="utf-8")
settings = settings.replace('LabeledContent("Version", value: "1.0.8")', 'LabeledContent("Version", value: "1.0.9")')
settings_path.write_text(settings, encoding="utf-8")

project_path = Path("NextJob/project.yml")
project = project_path.read_text(encoding="utf-8")
project = project.replace('MARKETING_VERSION: "1.0.8"', 'MARKETING_VERSION: "1.0.9"')
project = project.replace('CURRENT_PROJECT_VERSION: "9"', 'CURRENT_PROJECT_VERSION: "10"')
project_path.write_text(project, encoding="utf-8")

email_path = Path("NextJob/Services/EmailDeliveryService.swift")
email = email_path.read_text(encoding="utf-8")
email = email.replace("NextJob-iOS/1.0.8", "NextJob-iOS/1.0.9")
email_path.write_text(email, encoding="utf-8")

print("Next Job 1.0.9 performance optimisation applied.")
