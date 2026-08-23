import SwiftUI

struct SigningProfileView: View {
    @ObservedObject var store: SignerStore
    @State private var p12URL: URL?
    @State private var provisioningURL: URL?
    @State private var p12Password = ""
    @State private var pickerTarget: ProfilePickerTarget?
    @State private var isSaving = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    private enum ProfilePickerTarget: Int, Identifiable {
        case p12
        case provision
        var id: Int { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Apple Signing Profile", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                    Text("Replace the P12 certificate, provisioning profile and P12 password used by the GitHub signing runner. Values are encrypted on-device with GitHub’s repository public key before upload.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Certificate") {
                    Button {
                        pickerTarget = .p12
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
                        pickerTarget = .provision
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
            .sheet(item: $pickerTarget) { target in
                ProfileDocumentPicker(
                    onPick: { urls in
                        pickerTarget = nil
                        guard let url = urls.first else { return }
                        importSelectedFile(url, target: target)
                    },
                    onCancel: {
                        pickerTarget = nil
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    private func importSelectedFile(_ source: URL, target: ProfilePickerTarget) {
        successMessage = nil
        errorMessage = nil

        let requiredExtension = target == .p12 ? "p12" : "mobileprovision"
        guard source.pathExtension.lowercased() == requiredExtension else {
            errorMessage = "Choose a .\(requiredExtension) file."
            return
        }

        do {
            let local = try copyToPrivateProfileStaging(source)
            switch target {
            case .p12:
                removeLocalFileIfNeeded(p12URL)
                p12URL = local
            case .provision:
                removeLocalFileIfNeeded(provisioningURL)
                provisioningURL = local
            }
        } catch {
            errorMessage = "Unable to import \(source.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func copyToPrivateProfileStaging(_ source: URL) throws -> URL {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextSignerProfiles", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let safeName = source.lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let destination = folder.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func removeLocalFileIfNeeded(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
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
                    removeLocalFileIfNeeded(self.p12URL)
                    removeLocalFileIfNeeded(self.provisioningURL)
                    self.p12URL = nil
                    self.provisioningURL = nil
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
