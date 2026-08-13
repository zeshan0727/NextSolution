import SwiftUI

struct AutomationsView: View {
    @EnvironmentObject private var store: AutomationStore
    @EnvironmentObject private var emailStore: EmailAutomationStore

    @State private var filter: AutomationListFilter = .all
    @State private var selectedPlatform: AutomationPlatform?
    @State private var searchText = ""
    @State private var isAdding = false

    private var filteredAutomations: [SocialAutomation] {
        store.automations
            .filter { automation in
                let matchesSearch = searchText.isEmpty
                    || automation.title.localizedCaseInsensitiveContains(searchText)
                    || automation.contentText.localizedCaseInsensitiveContains(searchText)
                let matchesPlatform = selectedPlatform == nil || automation.platform == selectedPlatform
                let matchesFilter: Bool
                switch filter {
                case .all:
                    matchesFilter = true
                case .scheduled:
                    matchesFilter = automation.status == .scheduled || automation.status == .processing
                case .attention:
                    matchesFilter = [.needsSetup, .awaitingApproval, .failed].contains(automation.status)
                case .history:
                    matchesFilter = automation.status.isFinished
                }
                return matchesSearch && matchesPlatform && matchesFilter
            }
            .sorted { left, right in
                if left.status.isFinished == right.status.isFinished {
                    if left.status.isFinished {
                        return (left.completedAt ?? left.updatedAt) > (right.completedAt ?? right.updatedAt)
                    }
                    return left.scheduledAt < right.scheduledAt
                }
                return !left.status.isFinished
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                header
                emailAutomationCard
                listFilters
                platformFilters

                if filteredAutomations.isEmpty {
                    EmptyStateView(
                        icon: "paperplane.circle",
                        title: "No social automations found",
                        message: "Schedule a WhatsApp message, Instagram post or Story, or an X post. Email reminders are managed in the separate panel above."
                    )
                } else {
                    ForEach(filteredAutomations) { automation in
                        NavigationLink(value: automation.id) {
                            AutomationCard(
                                item: automation,
                                accountName: store.account(automation.accountID)?.displayName,
                                mediaURL: store.mediaURL(automation)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                store.duplicate(automation)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }

                            if automation.status == .paused {
                                Button {
                                    store.resume(automation)
                                } label: {
                                    Label("Resume", systemImage: "play.circle")
                                }
                            } else if !automation.status.isFinished {
                                Button {
                                    store.pause(automation)
                                } label: {
                                    Label("Pause", systemImage: "pause.circle")
                                }
                            }

                            Button(role: .destructive) {
                                store.delete(automation)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("Automations")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search social automations")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    AutomationConnectionsView()
                } label: {
                    Image(systemName: "network.badge.shield.half.filled")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(for: UUID.self) { id in
            AutomationDetailView(automationID: id)
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack {
                AutomationEditorView(automation: nil)
            }
            .environmentObject(store)
        }
        .onAppear {
            store.refreshDueStatuses()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scheduled automations")
                    .font(.title2.bold())
                Text("\(store.active.count) active social automation\(store.active.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "gearshape.2.fill")
                .font(.title3)
                .foregroundStyle(.nextOrange)
                .frame(width: 48, height: 48)
                .background(Color.nextOrange.opacity(0.15), in: Circle())
        }
        .padding(.top, 8)
    }

    private var emailAutomationCard: some View {
        NavigationLink {
            EmailAutomationSettingsView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "envelope.badge.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Email Reminder Automations")
                        .font(.headline)
                    Text(emailAutomationSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(emailStore.settings.enabled ? "Enabled" : "Off")
                        .font(.caption.bold())
                        .foregroundStyle(emailStore.settings.enabled ? Color.green : Color.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(15)
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.13), Color.purple.opacity(0.09), Color.nextCard],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(Color.blue.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var emailAutomationSubtitle: String {
        let settings = emailStore.settings
        guard settings.enabled else { return "Set a fixed recipient and choose Gmail, iCloud, SMTP, or Apple Mail." }
        let recipient = settings.recipient.isEmpty ? "Recipient not set" : settings.recipient
        return "\(settings.deliveryMethod.shortTitle) • \(recipient)"
    }

    private var listFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AutomationListFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        Text(option.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(filter == option ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(filter == option ? Color.nextOrange : Color.nextCard)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var platformFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                platformButton(
                    title: "All",
                    symbol: "square.grid.2x2.fill",
                    platform: nil,
                    color: .nextOrange
                )
                ForEach(AutomationPlatform.allCases) { platform in
                    platformButton(
                        title: platform.shortTitle,
                        symbol: platform.symbol,
                        platform: platform,
                        color: platform.color
                    )
                }
            }
        }
    }

    private func platformButton(
        title: String,
        symbol: String,
        platform: AutomationPlatform?,
        color: Color
    ) -> some View {
        let selected = selectedPlatform == platform
        return Button {
            selectedPlatform = platform
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.bold())
                .foregroundStyle(selected ? Color.white : color)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(selected ? color : Color.nextCard))
        }
        .buttonStyle(.plain)
    }
}
