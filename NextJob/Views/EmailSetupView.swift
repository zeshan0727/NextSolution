import SwiftUI

struct EmailSetupView: View {
    @StateObject private var emailStore = EmailConfigurationStore.shared
    @State private var endpoint = ""
    @State private var schedulerAPIKey = ""
    @State private var signature = ""
    @State private var preferredMode: EmailDeliveryMode = .gmailDirect
    @State private var isConnecting = false
    @State private var isDisconnecting = false
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showingNotice = false

    var body: some View {
        Form {
            Section {
                TextField("https://your-scheduler.example.com", text: $endpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Scheduler API key", text: $schedulerAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save Scheduler Settings") { saveScheduler() }
            } header: {
                Text("Next Reminder Email Scheduler")
            } footer: {
                Text("Use the same HTTPS scheduler URL and API key configured in Next Reminder. The API key is stored in the iPhone Keychain.")
            }

            Section("Gmail Connection") {
                if emailStore.isGmailConnected {
                    Label(emailStore.configuration.connectedEmail, systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Button(role: .destructive) {
                        disconnectGmail()
                    } label: {
                        Label(isDisconnecting ? "Disconnecting…" : "Disconnect Gmail", systemImage: "link.badge.minus")
                    }
                    .disabled(isDisconnecting)
                } else {
                    Button {
                        connectGmail()
                    } label: {
                        Label(isConnecting ? "Connecting Gmail…" : "Connect Gmail Account", systemImage: "envelope.badge.fill")
                    }
                    .disabled(isConnecting || !emailStore.isSchedulerConfigured)

                    if !emailStore.isSchedulerConfigured {
                        Label("Save the scheduler URL and API key first.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Email Defaults") {
                Picker("Preferred sending mode", selection: $preferredMode) {
                    ForEach(EmailDeliveryMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                TextEditor(text: $signature)
                    .frame(minHeight: 90)
                Button("Save Email Defaults") {
                    emailStore.update {
                        $0.preferredMode = preferredMode
                        $0.signature = signature
                    }
                    showNotice("Saved", "Email defaults have been updated.")
                }
            }

            Section {
                Text("Gmail Direct sends through your connected Next Reminder scheduler. Apple Mail Assisted opens the iPhone Mail composer for review before sending.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Email Setup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            endpoint = emailStore.configuration.schedulerEndpoint
            schedulerAPIKey = emailStore.schedulerAPIKey
            signature = emailStore.configuration.signature
            preferredMode = emailStore.configuration.preferredMode
        }
        .alert(noticeTitle, isPresented: $showingNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noticeMessage)
        }
    }

    private func saveScheduler() {
        do {
            try emailStore.saveScheduler(endpoint: endpoint, apiKey: schedulerAPIKey)
            showNotice("Scheduler Saved", "The email scheduler settings are ready.")
        } catch {
            showNotice("Could Not Save", error.localizedDescription)
        }
    }

    private func connectGmail() {
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                let record = try await GmailOAuthClient.shared.connect(using: emailStore)
                showNotice("Gmail Connected", record.emailAddress)
            } catch {
                showNotice("Gmail Connection Failed", error.localizedDescription)
            }
        }
    }

    private func disconnectGmail() {
        isDisconnecting = true
        Task {
            defer { isDisconnecting = false }
            do {
                try await GmailOAuthClient.shared.disconnect(using: emailStore)
                showNotice("Gmail Disconnected", "Direct email sending is now disabled.")
            } catch {
                showNotice("Could Not Disconnect", error.localizedDescription)
            }
        }
    }

    private func showNotice(_ title: String, _ message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }
}

struct OpenAISetupView: View {
    @StateObject private var openAIStore = OpenAIConfigurationStore.shared
    @State private var apiKey = ""
    @State private var model = "gpt-5-mini-2025-08-07"
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showingNotice = false

    private var selectedOption: OpenAIModelOption? {
        OpenAIModelOption.recommended.first { $0.id == model }
    }

    var body: some View {
        Form {
            Section {
                SecureField("OpenAI API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("Recommended model", selection: $model) {
                    ForEach(OpenAIModelOption.recommended) { option in
                        Text(option.title).tag(option.id)
                    }
                }

                TextField("Model ID", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if let selectedOption {
                    Text(selectedOption.tokenGroup)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Save OpenAI Settings") { save() }
            } header: {
                Text("OpenAI Email Drafting")
            } footer: {
                Text("GPT-5 Mini is recommended for reliable, lower-cost email drafting. Complimentary tokens are available only to eligible API organizations that opt into input/output data sharing and maintain a positive account balance. The listed models are eligible for that program, but they are not universally free. Your API key is stored in the iPhone Keychain and excluded from backups.")
            }

            Section("Status") {
                Label(
                    openAIStore.isConfigured ? "OpenAI is configured" : "OpenAI setup required",
                    systemImage: openAIStore.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(openAIStore.isConfigured ? .green : .orange)
                LabeledContent("Model", value: openAIStore.model)
            }
        }
        .navigationTitle("OpenAI Setup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            apiKey = openAIStore.apiKey
            model = openAIStore.model
        }
        .alert(noticeTitle, isPresented: $showingNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noticeMessage)
        }
    }

    private func save() {
        do {
            try openAIStore.save(apiKey: apiKey, model: model)
            showNotice("OpenAI Saved", "The AI email assistant is ready with \(model).")
        } catch {
            showNotice("Could Not Save", error.localizedDescription)
        }
    }

    private func showNotice(_ title: String, _ message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }
}
