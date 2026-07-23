import SwiftUI

struct SMSImportPreferencesView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var enabled = true
    @State private var matchText = "**6760"
    @State private var destinationAccountID: UUID?
    @State private var requestedScan = false

    var body: some View {
        Form {
            Section {
                Toggle("Automatic Import", isOn: $enabled)
                TextField("Required SMS text", text: $matchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Save to Account", selection: $destinationAccountID) {
                    ForEach(store.activeAccounts) { account in
                        Text("\(account.name) · \(account.currencyCode)")
                            .tag(Optional(account.id))
                    }
                }
            } header: {
                Text("Matching")
            } footer: {
                Text("Only SMS messages containing this exact text are imported. For your card, keep **6760 and choose Credit Card.")
            }

            Section {
                Button {
                    savePreferences()
                    store.requestSMSRescan()
                    requestedScan = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                        store.reload()
                        requestedScan = false
                    }
                } label: {
                    Label("Scan Latest Matching SMS", systemImage: "arrow.clockwise.circle.fill")
                }
                .disabled(cleanedMatchText.isEmpty || destinationAccountID == nil)

                if requestedScan {
                    Label("Request sent. Check status again in about 5 seconds.", systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Test & Recovery")
            } footer: {
                Text("This also recovers a recent matching SMS that arrived before the importer service started.")
            }

            Section("Importer Status") {
                LabeledContent("Last Check") {
                    Text(lastCheckText)
                        .foregroundStyle(.secondary)
                }
                Text(store.settings.smsImporterLastResult ?? "No status reported yet. Install or update the RootHide SMS Import package.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink("Vendor Category Rules") {
                    VendorRulesView()
                }
            } footer: {
                Text("The full SMS remains the transaction description. The merchant name is categorized using your vendor rules.")
            }
        }
        .navigationTitle("SMS Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: savePreferences)
                    .disabled(cleanedMatchText.isEmpty || destinationAccountID == nil)
            }
        }
        .onAppear {
            enabled = store.settings.smsAutoImportEnabled
            matchText = store.settings.smsMatchText
            destinationAccountID = store.settings.smsDestinationAccountID ?? store.defaultAccountID
        }
        .onChange(of: store.settings.smsImporterLastCheck) { _ in
            requestedScan = false
        }
    }

    private var cleanedMatchText: String {
        matchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var lastCheckText: String {
        guard let date = store.settings.smsImporterLastCheck else { return "Never" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private func savePreferences() {
        store.updateSMSAutoImport(enabled)
        store.updateSMSPreferences(
            matchText: cleanedMatchText,
            destinationAccountID: destinationAccountID
        )
    }
}
