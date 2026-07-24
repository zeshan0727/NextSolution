// MARK: - Sources/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(ThemePreference.storageKey) private var themeRawValue = ThemePreference.system.rawValue
    @State private var showingEditProfile = false
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Section("Profile") {
                Button("Edit customer profile") { showingEditProfile = true }
            }

            Section("Appearance") {
                Picker("Theme", selection: $themeRawValue) {
                    ForEach(ThemePreference.allCases) { theme in
                        Text(theme.rawValue).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Test tools") {
                Button {
                    store.loadTestData()
                } label: {
                    Label("Add demo request", systemImage: "testtube.2")
                }
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Delete all local test data", systemImage: "trash")
                }
            } footer: {
                Text("The final public release must connect authenticated requests, encrypted uploads, server-side status updates and a verified privacy policy before test mode is removed.")
            }

            Section("About") {
                LabeledContent("App", value: AppConfiguration.appName)
                LabeledContent("Version", value: "\(AppConfiguration.version) (\(AppConfiguration.build))")
                Link("KB Accountant website", destination: AppConfiguration.websiteURL)
                NavigationLink("Test-build privacy note") {
                    PrivacyTestView()
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditProfile) {
            if let profile = store.profile {
                EditProfileView(profile: profile)
            }
        }
        .confirmationDialog(
            "Delete all local test data?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                store.deleteAllLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the profile, requests, appointments and imported documents from this device.")
        }
    }
}

private struct EditProfileView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var profile: UserProfile

    init(profile: UserProfile) {
        _profile = State(initialValue: profile)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Full name", text: $profile.fullName)
                TextField("Email", text: $profile.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("Phone", text: $profile.phone)
                    .keyboardType(.phonePad)
                TextField("Company", text: $profile.companyName)
                Picker("Primary market", selection: $profile.jurisdiction) {
                    ForEach(Jurisdiction.allCases.filter { $0 != .crossBorder }) { market in
                        Text("\(market.flag) \(market.rawValue)").tag(market)
                    }
                }
                Picker("Customer type", selection: $profile.customerType) {
                    ForEach(CustomerType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateProfile(profile)
                        dismiss()
                    }
                    .disabled(profile.fullName.isEmpty || !profile.email.contains("@"))
                }
            }
        }
    }
}

private struct PrivacyTestView: View {
    var body: some View {
        List {
            Section("Test build 0.1.0") {
                Text("Profile information, test service requests, consultation details and imported files are stored locally inside the app container.")
                Text("This build does not transmit requests or documents to KB Accountant. Testers should use sample or non-sensitive information.")
                Text("Delete the app or use Settings → Delete all local test data to remove the prototype records from the device. Device backups may follow the iPhone's backup settings.")
            }
            Section("Before publication") {
                Text("KBA must approve a production privacy policy that accurately describes authentication, backend processing, document storage, retention, account deletion and regional responsibilities.")
            }
        }
        .navigationTitle("Privacy Note")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sources/Account/AccountView.swift
import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                if let profile = store.profile {
                    Section {
                        HStack(spacing: 14) {
                            BrandMark(size: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.fullName)
                                    .font(.headline)
                                Text(profile.email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("\(profile.jurisdiction.flag) \(profile.jurisdiction.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }

                Section("Customer tools") {
                    NavigationLink {
                        ConsultationsView()
                    } label: {
                        Label("Consultations", systemImage: "calendar")
                    }
                    NavigationLink {
                        ContactView()
                    } label: {
                        Label("Contact KBA", systemImage: "message.fill")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings & Testing", systemImage: "gearshape.fill")
                    }
                }

                if AppConfiguration.isLocalTestMode {
                    Section { LocalTestBanner() }
                }
            }
            .navigationTitle("Account")
        }
    }
}
