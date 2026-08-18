import SwiftUI
import UIKit

struct NextSignerRootView: View {
    @StateObject private var store = SignerStore()

    var body: some View {
        TabView {
            NextSignerSignView(store: store)
                .tabItem { Label("Sign", systemImage: "signature") }

            NextSignerActivityView(store: store)
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }

            NextSignerSettingsView(store: store)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.accentColor)
    }
}

private struct NextSignerSignView: View {
    @ObservedObject var store: SignerStore
    @State private var showsPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    appCard
                    detailsCard
                    localSigningCard
                    publishCard
                }
                .padding()
            }
            .navigationTitle("Next Signer")
            .sheet(isPresented: $showsPicker) {
                UIKitDocumentPicker(
                    onPick: { url in
                        showsPicker = false
                        let name = url.lastPathComponent.lowercased()
                        guard name.hasSuffix(".ipa") || name.hasSuffix(".tipa") else {
                            store.errorMessage = "Please choose an .ipa or .tipa file."
                            return
                        }
                        store.importIPA(from: url)
                    },
                    onCancel: { showsPicker = false }
                )
                .ignoresSafeArea()
            }
            .nextSignerAlert(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pick. Sign. Publish.", systemImage: "checkmark.seal.fill")
                .font(.title2.bold())
            Text("The IPA is signed locally on this iPhone first. Only after signing succeeds can you publish the signed IPA to nextsolution.cc/install/.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                if let url = store.request.ipaURL {
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox.fill")
                            .font(.title2)
                            .frame(width: 42, height: 42)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.lastPathComponent)
                                .font(.headline)
                                .lineLimit(2)
                            Text(fileSizeText(url))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(role: .destructive) { store.clearSelectedIPA() } label: {
                            Image(systemName: "trash")
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 34))
                        Text("No IPA selected")
                            .font(.headline)
                        Text("Choose an IPA or TIPA from Files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                Button { showsPicker = true } label: {
                    Label(store.request.ipaURL == nil ? "Choose IPA / TIPA" : "Choose Another IPA / TIPA", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        } label: {
            Label("App", systemImage: "app.dashed")
        }
    }

    private var detailsCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                TextField("App name", text: $store.request.appName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                TextField("Bundle ID", text: $store.request.bundleID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textFieldStyle(.roundedBorder)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: store.request.isValidBundleID ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(store.request.isValidBundleID ? .green : .orange)
                    Text(store.request.isValidBundleID
                         ? "Bundle identifier format is valid. Keep it under com.nextsolution.* when using your wildcard Ad Hoc profile."
                         : "Enter a valid reverse-DNS bundle identifier, for example com.nextsolution.myapp.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Signing identity", systemImage: "number")
        }
    }

    private var localSigningCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    credentialIndicator("P12", ready: store.hasP12)
                    Spacer()
                    credentialIndicator("Profile", ready: store.hasProvisioningProfile)
                    Spacer()
                    credentialIndicator("Password", ready: store.p12PasswordIsStored)
                }

                if store.isWorking, store.activeJob?.stage == .signing {
                    ProgressView(value: store.progress)
                    Text(store.activeJob?.detail ?? "Signing locally…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let signed = store.signedResult {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Signed locally and verified", systemImage: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.subheadline.bold())
                        Text("\(signed.appName) · \(signed.version) (\(signed.build))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(signed.bundleID)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        ShareLink(item: signed.ipaURL) {
                            Label("Export Signed IPA", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button { store.signLocally() } label: {
                    Label(store.isWorking && store.activeJob?.stage == .signing ? "Signing Locally…" : "1. Sign App Locally", systemImage: "signature")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!store.request.isReady || !store.credentialsReady || store.isWorking)

                if !store.credentialsReady {
                    Text("Import your P12, provisioning profile and P12 password once in Settings. They remain on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Step 1 · Local signing", systemImage: "lock.shield")
        }
    }

    private var publishCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                if store.isWorking, store.activeJob?.stage == .uploading {
                    ProgressView(value: store.progress)
                    Text(store.activeJob?.detail ?? "Publishing signed IPA…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let success = store.successMessage {
                    Label(success, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button { store.publishSigned() } label: {
                    Label(store.isWorking && store.activeJob?.stage == .uploading ? "Publishing Signed IPA…" : "2. Publish Signed App", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.signedResult == nil || store.isWorking || !store.tokenIsStored)

                if store.signedResult == nil {
                    Text("Publishing remains locked until local signing succeeds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !store.tokenIsStored {
                    Text("Add your GitHub token once in Settings to publish the already-signed IPA.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Step 2 · Publish", systemImage: "globe")
        }
    }

    private func credentialIndicator(_ title: String, ready: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(ready ? .green : .secondary)
            Text(title).font(.caption2)
        }
    }

    private func fileSizeText(_ url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize else { return "IPA / TIPA" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct NextSignerActivityView: View {
    @ObservedObject var store: SignerStore

    var body: some View {
        NavigationStack {
            List {
                if let job = store.activeJob {
                    Section("Current job") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: icon(for: job.stage))
                                Text(job.requestedAppName).font(.headline)
                                Spacer()
                                Text(job.stage.rawValue).font(.caption.bold())
                            }
                            Text(job.sourceName).font(.caption).foregroundStyle(.secondary)
                            Text(job.requestedBundleID).font(.caption2).foregroundStyle(.secondary)
                            Text(job.detail).font(.footnote)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "signature")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text("No signing jobs yet")
                                .font(.headline)
                            Text("Local signing and publishing activity will appear here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }

                if let signed = store.signedResult {
                    Section("Signed output") {
                        Text(signed.ipaURL.lastPathComponent)
                            .font(.footnote)
                        ShareLink(item: signed.ipaURL) {
                            Label("Export Signed IPA", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section("Installer") {
                    Link(destination: URL(string: "https://nextsolution.cc/install/")!) {
                        Label("Open Next Solution Private Apps", systemImage: "safari")
                    }
                }
            }
            .navigationTitle("Activity")
            .nextSignerAlert(store)
        }
    }

    private func icon(for stage: SigningJob.Stage) -> String {
        switch stage {
        case .preparing: return "gearshape.2"
        case .signing: return "signature"
        case .signed: return "checkmark.seal.fill"
        case .uploading: return "arrow.up.circle"
        case .published: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }
}

private struct NextSignerSettingsView: View {
    @ObservedObject var store: SignerStore
    @State private var revealToken = false
    @State private var revealPassword = false
    @State private var credentialPicker: CredentialPicker?

    var body: some View {
        NavigationStack {
            Form {
                Section("Local signing certificate") {
                    HStack {
                        Label("P12 certificate", systemImage: "key.fill")
                        Spacer()
                        Text(store.hasP12 ? "Imported" : "Missing")
                            .foregroundColor(store.hasP12 ? .green : .secondary)
                    }
                    Button(store.hasP12 ? "Replace P12" : "Import P12") {
                        credentialPicker = .p12
                    }

                    HStack {
                        Label("Provisioning profile", systemImage: "person.badge.shield.checkmark")
                        Spacer()
                        Text(store.hasProvisioningProfile ? "Imported" : "Missing")
                            .foregroundColor(store.hasProvisioningProfile ? .green : .secondary)
                    }
                    Button(store.hasProvisioningProfile ? "Replace Profile" : "Import .mobileprovision") {
                        credentialPicker = .provisioning
                    }

                    if revealPassword {
                        TextField("P12 password", text: $store.p12Password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("P12 password", text: $store.p12Password)
                    }
                    Toggle("Show P12 password", isOn: $revealPassword)
                    Button("Save P12 Password to Keychain") { store.saveP12Password() }

                    Label(store.credentialsReady ? "Local signing ready" : "Complete the three signing items above",
                          systemImage: store.credentialsReady ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .font(.caption)
                        .foregroundColor(store.credentialsReady ? .green : .secondary)

                    Text("The P12 and provisioning profile are stored inside Next Signer's protected app container. The password is stored in the iOS Keychain. They are not sent to GitHub during signing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("GitHub publishing") {
                    TextField("Owner", text: $store.configuration.owner)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Repository", text: $store.configuration.repository)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Branch", text: $store.configuration.branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Fine-grained GitHub token") {
                    if revealToken {
                        TextField("github_pat_…", text: $store.token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("github_pat_…", text: $store.token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Toggle("Show token", isOn: $revealToken)
                    Button("Save Token to Keychain") { store.saveToken() }
                    Label(store.tokenIsStored ? "Token stored on this device" : "Token not configured",
                          systemImage: store.tokenIsStored ? "lock.fill" : "lock.open")
                        .font(.caption)
                        .foregroundColor(store.tokenIsStored ? .green : .secondary)
                }

                Section("Required GitHub permission") {
                    Label("Contents: Read and write", systemImage: "doc.badge.gearshape")
                    Text("The token should be a fine-grained personal access token scoped only to zeshan0727/NextSolution. Next Signer no longer needs Actions permission because signing happens locally before publishing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onDisappear { store.persistConfiguration() }
            .sheet(item: $credentialPicker) { kind in
                UIKitDocumentPicker(
                    onPick: { url in
                        credentialPicker = nil
                        let lower = url.lastPathComponent.lowercased()
                        switch kind {
                        case .p12:
                            guard lower.hasSuffix(".p12") || lower.hasSuffix(".pfx") else {
                                store.errorMessage = "Choose a .p12 or .pfx certificate file."
                                return
                            }
                            store.importCredential(from: url, kind: .p12)
                        case .provisioning:
                            guard lower.hasSuffix(".mobileprovision") else {
                                store.errorMessage = "Choose a .mobileprovision file."
                                return
                            }
                            store.importCredential(from: url, kind: .provisioning)
                        }
                    },
                    onCancel: { credentialPicker = nil }
                )
                .ignoresSafeArea()
            }
            .nextSignerAlert(store)
        }
    }

    private enum CredentialPicker: Int, Identifiable {
        case p12
        case provisioning
        var id: Int { rawValue }
    }
}

private struct UIKitDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            documentTypes: ["public.item", "public.data", "public.archive", "com.apple.itunes.ipa"],
            in: .import
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: UIKitDocumentPicker
        init(parent: UIKitDocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.onCancel()
                return
            }
            parent.onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

private extension View {
    func nextSignerAlert(_ store: SignerStore) -> some View {
        alert("Next Signer", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }
}
