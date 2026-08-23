import SwiftUI
import UniformTypeIdentifiers

struct SigningProfileView: View {
    @ObservedObject var store: SignerStore
    @State private var p12URL: URL?
    @State private var provisioningURL: URL?
    @State private var p12Password = ""
    @State private var showP12Picker = false
    @State private var showProvisionPicker = false
    @State private var isSaving = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Apple Signing Profile", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                    Text("Replace the P12 certificate, provisioning profile and P12 password used by the GitHub signing runner. Values are encrypted on-device with GitHub’s repository public key before upload and are not stored by Next Signer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Certificate") {
                    Button {
                        showP12Picker = true
                    } label: {
                        HStack {
                            Label("Choose P12", systemImage: "key.fill")
                            Spacer()
                            if let p12URL {
                                Text(p12URL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }

                    SecureField("P12 password", text: $p12Password)
                        .textContentType(.password)
                }

                Section("Provisioning Profile") {
                    Button {
                        showProvisionPicker = true
                    } label: {
                        HStack {
                            Label("Choose .mobileprovision", systemImage: "doc.badge.gearshape")
                            Spacer()
                            if let provisioningURL {
                                Text(provisioningURL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        saveProfile()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            } else {
                                Label("Save Signing Profile", systemImage: "square.and.arrow.down.fill")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isSaving || p12URL == nil || provisioningURL == nil || p12Password.isEmpty || !store.tokenIsStored)

                    if let successMessage {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote.bold())
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                } footer: {
                    Text("The saved GitHub PAT needs Secrets: Read and write permission for this repository to change signing material.")
                }
            }
            .navigationTitle("Signing Profile")
            .fileImporter(isPresented: $showP12Picker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                handle(result, expectedExtension: "p12", target: .p12)
            }
            .fileImporter(isPresented: $showProvisionPicker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                handle(result, expectedExtension: "mobileprovision", target: .provision)
            }
        }
    }

    private enum Target { case p12, provision }

    private func handle(_ result: Result<[URL], Error>, expectedExtension: String, target: Target) {
        successMessage = nil
        errorMessage = nil
        do {
            guard let url = try result.get().first else { return }
            guard url.pathExtension.lowercased() == expectedExtension else {
                errorMessage = "Choose a .\(expectedExtension) file."
                return
            }
            switch target {
            case .p12: p12URL = url
            case .provision: provisioningURL = url
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveProfile() {
        guard let p12URL, let provisioningURL else { return }
        let token = store.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Save your GitHub token in Settings first."
            return
        }

        isSaving = true
        successMessage = nil
        errorMessage = nil
        let password = p12Password
        let configuration = store.configuration

        Task {
            do {
                let service = SigningProfileService(token: token, configuration: configuration)
                try await service.saveSigningProfile(p12URL: p12URL, provisioningURL: provisioningURL, password: password)
                await MainActor.run {
                    isSaving = false
                    p12Password = ""
                    successMessage = "Signing profile saved successfully."
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
