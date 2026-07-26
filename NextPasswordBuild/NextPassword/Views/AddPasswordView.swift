import SwiftUI

struct AddPasswordView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var site = ""
    @State private var username = ""
    @State private var link = ""
    @State private var notes = ""
    @State private var prefix = "MdMr@0727es"
    @State private var sequence = 1
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Website") {
                    TextField("Site or app name", text: $site)
                    TextField("Username or email", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("https://example.com", text: $link)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                Section("Familiar Series") {
                    TextField("Memorable prefix", text: $prefix)
                    Stepper("Sequence: \(sequence)", value: $sequence, in: 1...9999)
                    Button("Generate Password") {
                        password = PasswordGenerator.familiar(prefix: prefix, sequence: sequence)
                    }
                    TextField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
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
                    .disabled(site.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                }
            }
            .onAppear {
                password = PasswordGenerator.familiar(prefix: prefix, sequence: sequence)
            }
        }
    }
}
