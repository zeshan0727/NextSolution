import SwiftUI

struct AddPasswordView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var site = ""
    @State private var username = ""
    @State private var link = ""
    @State private var notes = ""
    @State private var password = "MpMr@"

    var body: some View {
        NavigationStack {
            Form {
                Section("Website") {
                    TextField("Site or app name", text: $site)
                        .onChange(of: site) { newValue in
                            password = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "MpMr@"
                                : PasswordGenerator.websiteBased(site: newValue)
                        }
                    Text("Your password is predicted from this website name.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Username or email", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("https://example.com", text: $link)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }

                Section("Generated Password") {
                    HStack {
                        Text(password)
                            .font(.system(.title3, design: .monospaced).bold())
                        Spacer()
                        Button {
                            password = PasswordGenerator.websiteBased(site: site)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Format: MpMr@ + 2 letters + 2 numbers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("New Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vault.add(.init(site: site, username: username, password: password, link: link, notes: notes))
                        dismiss()
                    }
                    .disabled(site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password == "MpMr@")
                }
            }
        }
    }
}
