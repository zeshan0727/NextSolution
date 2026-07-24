// MARK: - Sources/Home/HomeView.swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedTab: AppTab

    private var firstName: String {
        store.profile?.fullName.split(separator: " ").first.map(String.init) ?? "Client"
    }

    private var featuredServices: [KBAService] {
        ServiceCatalog.services(for: store.profile?.jurisdiction).prefix(3).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 13) {
                        BrandMark(size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hello, \(firstName)")
                                .font(.title2.bold())
                            Text("How can KBA support you today?")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if AppConfiguration.isLocalTestMode {
                        LocalTestBanner()
                    }

                    HStack(spacing: 12) {
                        DashboardMetric(title: "Requests", value: "\(store.requests.count)", icon: "tray.full.fill")
                        DashboardMetric(title: "Documents", value: "\(store.documents.count)", icon: "folder.fill")
                        DashboardMetric(title: "Meetings", value: "\(store.consultations.count)", icon: "calendar")
                    }

                    Text("Quick actions")
                        .font(.title3.bold())

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        NavigationLink {
                            ServicesView(embedded: true)
                        } label: {
                            QuickActionCard(title: "Request a service", icon: "plus.circle.fill")
                        }
                        NavigationLink {
                            ConsultationsView()
                        } label: {
                            QuickActionCard(title: "Book consultation", icon: "calendar.badge.plus")
                        }
                        Button {
                            selectedTab = .documents
                        } label: {
                            QuickActionCard(title: "Add documents", icon: "doc.badge.plus")
                        }
                        NavigationLink {
                            ContactView()
                        } label: {
                            QuickActionCard(title: "Contact KBA", icon: "message.fill")
                        }
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Text("Recommended services")
                            .font(.title3.bold())
                        Spacer()
                        Button("View all") { selectedTab = .services }
                            .font(.subheadline.weight(.semibold))
                    }

                    ForEach(featuredServices) { service in
                        NavigationLink {
                            ServiceDetailView(service: service)
                        } label: {
                            ServiceCard(service: service)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("KBA Client")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct DashboardMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(BrandColor.blue)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct QuickActionCard: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(BrandColor.blue)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(minHeight: 104)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.07))
        }
    }
}

// MARK: - Sources/Root/RootView.swift
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.profile == nil {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .tint(BrandColor.blue)
    }
}

enum AppTab: Hashable {
    case home, services, requests, documents, account
}

private struct MainTabView: View {
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView(selectedTab: $selection)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            ServicesView()
                .tabItem { Label("Services", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.services)

            RequestsView()
                .tabItem { Label("Requests", systemImage: "tray.full.fill") }
                .tag(AppTab.requests)

            DocumentsView()
                .tabItem { Label("Documents", systemImage: "folder.fill") }
                .tag(AppTab.documents)

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle.fill") }
                .tag(AppTab.account)
        }
    }
}

// MARK: - Sources/KBAClientApp.swift
import SwiftUI

@main
struct KBAClientApp: App {
    @StateObject private var store = AppStore()
    @AppStorage(ThemePreference.storageKey) private var themeRawValue = ThemePreference.system.rawValue

    private var selectedTheme: ThemePreference {
        ThemePreference(rawValue: themeRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(selectedTheme.colorScheme)
        }
    }
}
