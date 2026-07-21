import SwiftUI

struct AutomationConnectionsView: View {
    @EnvironmentObject private var store: AutomationStore
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var isAddingAccount = false
    @State private var selectedAccount: AutomationAccount?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                schedulerSection
                accountsSection
                requirementsSection
            }
            .padding(16)
            .padding(.bottom, 30)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("Automation Connections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isAddingAccount = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .onAppear {
            endpoint = store.cloudEndpoint
            apiKey = store.cloudAPIKey
        }
        .sheet(isPresented: $isAddingAccount) {
            NavigationStack {
                AutomationAccountEditorView(account: nil)
            }
            .environmentObject(store)
        }
        .sheet(item: $selectedAccount) { account in
            NavigationStack {
                AutomationAccountEditorView(account: account)
            }
            .environmentObject(store)
        }
    }

    private var schedulerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Automatic Scheduler")

            TextField("HTTPS server URL", text: $endpoint)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .padding(14)
                .nextCard()

            SecureField("Scheduler API key", text: $apiKey)
                .padding(14)
                .nextCard()

            HStack(spacing: 12) {
                Button("Save Securely") {
                    store.saveCloud(endpoint: endpoint, key: apiKey)
                }
                .buttonStyle(OrangeActionButtonStyle())

                Button {
                    Task {
                        await store.testCloud(endpoint: endpoint, key: apiKey)
                    }
                } label: {
                    Image(systemName: store.isTesting ? "hourglass" : "network")
                        .frame(width: 46, height: 46)
                        .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(store.isTesting)
            }

            if let message = store.connectionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("The scheduler receives automatic jobs immediately and runs them at the selected time. Use a trusted HTTPS service; social passwords are never stored in this app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Publishing Accounts", trailing: "No passwords")

            if store.accounts.isEmpty {
                Button {
                    isAddingAccount = true
                } label: {
                    Label(
                        "Add WhatsApp, Instagram, or X account",
                        systemImage: "person.badge.plus"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .nextCard()
                }
                .buttonStyle(.plain)
            } else {
                ForEach(store.accounts) { account in
                    Button {
                        selectedAccount = account
                    } label: {
                        accountRow(account)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func accountRow(_ account: AutomationAccount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(for: account.accountType.platform))
                .font(.title3)
                .foregroundStyle(.nextOrange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(account.displayName)
                    .font(.headline)
                Text(account.accountType.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(
                systemName: account.isReadyForAutomaticPublishing
                    ? "checkmark.shield.fill"
                    : "hand.tap.fill"
            )
            .foregroundStyle(account.isReadyForAutomaticPublishing ? Color.green : Color.orange)
        }
        .padding(14)
        .nextCard()
    }

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Requirements")
            requirementRow(
                icon: "message.fill",
                title: "WhatsApp",
                text: "Automatic messages require WhatsApp Business Cloud. Personal WhatsApp uses Assisted mode."
            )
            requirementRow(
                icon: "camera.fill",
                title: "Instagram",
                text: "Posts require a Professional account. Automatic Stories require a Business account."
            )
            requirementRow(
                icon: "text.bubble.fill",
                title: "X",
                text: "Automatic posts require an X developer app and authenticated write access."
            )
        }
    }

    private func requirementRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.nextOrange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .nextCard()
    }

    private func symbol(for platform: AutomationAccountPlatform) -> String {
        switch platform {
        case .whatsapp: return "message.fill"
        case .instagram: return "camera.fill"
        case .x: return "text.bubble.fill"
        }
    }
}

struct AutomationAccountEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AutomationStore

    let account: AutomationAccount?

    @State private var displayName: String
    @State private var handleOrNumber: String
    @State private var remoteAccountID: String
    @State private var accountType: AutomationAccountType
    @State private var automaticPublishingEnabled: Bool
    @State private var showDeleteConfirmation = false

    init(account: AutomationAccount?) {
        self.account = account
        _displayName = State(initialValue: account?.displayName ?? "")
        _handleOrNumber = State(initialValue: account?.handleOrNumber ?? "")
        _remoteAccountID = State(initialValue: account?.remoteAccountID ?? "")
        _accountType = State(initialValue: account?.accountType ?? .whatsappBusiness)
        _automaticPublishingEnabled = State(
            initialValue: account?.automaticPublishingEnabled ?? false
        )
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TextField("Account label", text: $displayName)
                    .padding(14)
                    .nextCard()

                TextField("Handle or business number", text: $handleOrNumber)
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .nextCard()

                Menu {
                    ForEach(AutomationAccountType.allCases) { option in
                        Button(option.title) { accountType = option }
                    }
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(.nextOrange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Account type").font(.headline)
                            Text(accountType.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .nextCard()
                }
                .buttonStyle(.plain)

                TextField("Remote account ID from scheduler", text: $remoteAccountID)
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .nextCard()

                Toggle("Enable automatic publishing", isOn: $automaticPublishingEnabled)
                    .padding(14)
                    .nextCard()

                Text("The remote ID refers to the OAuth-connected account on your scheduler. Never enter a social-media password here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(account == nil ? "Add Account" : "Save Account") {
                    saveAccount()
                }
                .buttonStyle(OrangeActionButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)

                if account != nil {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle(account == nil ? "Add Account" : "Edit Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .confirmationDialog(
            "Delete this account?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let account {
                    store.deleteAccount(account)
                }
                dismiss()
            }
        }
    }

    private func saveAccount() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = handleOrNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteID = remoteAccountID.trimmingCharacters(in: .whitespacesAndNewlines)

        if var existing = account {
            existing.displayName = name
            existing.handleOrNumber = handle
            existing.remoteAccountID = remoteID
            existing.accountType = accountType
            existing.automaticPublishingEnabled = automaticPublishingEnabled
            store.updateAccount(existing)
        } else {
            store.addAccount(
                AutomationAccount(
                    displayName: name,
                    handleOrNumber: handle,
                    remoteAccountID: remoteID,
                    accountType: accountType,
                    automaticPublishingEnabled: automaticPublishingEnabled
                )
            )
        }
        dismiss()
    }
}
