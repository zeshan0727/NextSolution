import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var store: JobStore
    @State private var showingNewJob = false
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tabItem { Label("Summary", systemImage: "rectangle.grid.2x2.fill") }
                    .tag(0)

                JobsView()
                    .tabItem { Label("Jobs", systemImage: "briefcase.fill") }
                    .tag(1)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(2)
            }

            Button {
                showingNewJob = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                    .shadow(color: .blue.opacity(0.32), radius: 14, y: 8)
            }
            .accessibilityLabel("Add Job")
            .padding(.trailing, 20)
            .padding(.bottom, 72)
        }
        .preferredColorScheme(store.settings.theme.colorScheme)
        .sheet(isPresented: $showingNewJob) {
            JobEditorView().environmentObject(store)
        }
        .alert("Save Error", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "Unknown error")
        }
    }
}
