import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: ReminderStore
    @AppStorage("NextReminder.ThemeMode") private var themeModeRaw = AppThemeMode.system.rawValue
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequesting = false

    private var selectedTheme: Binding<AppThemeMode> {
        Binding(
            get: { AppThemeMode(rawValue: themeModeRaw) ?? .system },
            set: { themeModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                appearanceSection
                notificationSection
                managementSection
                automationSection
                aboutSection
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshNotificationStatus() }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Appearance")
            VStack(spacing: 8) {
                ForEach(AppThemeMode.allCases) { mode in
                    Button {
                        selectedTheme.wrappedValue = mode
                    } label: {
                        HStack {
                            Image(systemName: mode.symbol)
                                .foregroundStyle(mode == .dark ? Color.purple : mode == .light ? Color.yellow : Color.nextOrange)
                                .frame(width: 28)
                            Text(mode.title)
                            Spacer()
                            Image(systemName: selectedTheme.wrappedValue == mode ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedTheme.wrappedValue == mode ? Color.nextOrange : Color.secondary)
                        }
                        .padding(14)
                        .nextCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Notifications")
            HStack {
                Image(systemName: notificationIcon)
                    .foregroundStyle(notificationColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notification Permission")
                    Text(notificationStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if authorizationStatus == .notDetermined {
                    Button(isRequesting ? "Requesting…" : "Enable") {
                        Task { await requestNotifications() }
                    }
                    .disabled(isRequesting)
                } else {
                    Button("Settings") { NotificationManager.shared.openSystemSettings() }
                }
            }
            .padding(14)
            .nextCard()

            Text("Notifications are used for reminder alerts, automation approvals, assisted publishing, and status checks.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Reminder Management")
            NavigationLink {
                CategoryManagementView()
            } label: {
                settingsRow(
                    icon: "line.3.horizontal.decrease.circle.fill",
                    title: "Reminder Filters",
                    subtitle: "Rename Personal and General or add custom filters"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Social Automations")
            NavigationLink {
                AutomationConnectionsView()
            } label: {
                settingsRow(
                    icon: "network.badge.shield.half.filled",
                    title: "Accounts & Scheduler",
                    subtitle: "Connect WhatsApp Business, Instagram, X, and an HTTPS scheduler"
                )
            }
            .buttonStyle(.plain)

            Text("Social passwords are never stored. Automatic mode uses OAuth-connected accounts on your scheduler; personal or unsupported accounts use approval or assisted mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "About")
            VStack(spacing: 0) {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.nextOrange.opacity(0.18))
                        Image(systemName: "bell.badge.fill")
                            .font(.title2)
                            .foregroundStyle(.nextOrange)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next Reminder").font(.headline)
                        Text("Version 1.1.0 • iOS 16.0+")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)

                Divider().opacity(0.2).padding(.leading, 14)

                HStack {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(.nextOrange)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Credit")
                        Text("Next Solution - Zeshan 0727")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
            }
            .nextCard()
        }
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.nextOrange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .nextCard()
    }

    private var notificationStatusText: String {
        switch authorizationStatus {
        case .authorized: return "Allowed"
        case .denied: return "Denied — open iOS Settings to enable"
        case .provisional: return "Provisional"
        case .ephemeral: return "Temporary permission"
        case .notDetermined: return "Not requested yet"
        @unknown default: return "Unknown"
        }
    }

    private var notificationIcon: String {
        authorizationStatus == .authorized ? "bell.badge.fill" : "bell.slash.fill"
    }

    private var notificationColor: Color {
        authorizationStatus == .authorized ? .green : .nextOrange
    }

    private func refreshNotificationStatus() async {
        authorizationStatus = await NotificationManager.shared.authorizationStatus()
    }

    private func requestNotifications() async {
        isRequesting = true
        _ = await store.requestNotificationPermission()
        await refreshNotificationStatus()
        isRequesting = false
    }
}
