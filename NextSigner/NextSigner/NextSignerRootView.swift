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
                    onCancel: {
                        showsPicker = false
                    }
                )
                .ignoresSafeArea()
            }
            .alert("Next Signer", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "Unknown error")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pick. Sign. Publish.", systemImage: "checkmark.seal.fill")
                .font(.title2.bold())
            Text("Choose an IPA or TIPA from Files. After setup, one tap sends it to your private signing workflow and publishes the signed build to nextsolution.cc/install/.")
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

                        Button(role: .destructive) {
                            store.clearSelectedIPA()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 34))
                        Text("No IPA selected")
                            .font(.headline)
                        Text("Uses the native iOS document picker in unrestricted file mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                Button {
                    showsPicker = true
                } label: {
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
                         ? "Bundle identifier format is valid. Keep it under com.nextsolution.* when using the wildcard Ad Hoc profile."
                         : "Enter a valid reverse-DNS bundle identifier, for example com.nextsolution.myapp.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Signing identity", systemImage: "number")
        }
    }

    private var publishCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                if store.isWorking {
                    ProgressView(value: store.progress)
                    Text(store.activeJob?.detail ?? "Working…")
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

                Button {
                    store.signAndPublish()
                } label: {
                    Label(store.isWorking ? "Signing & Publishing…" : "Sign & Publish", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!store.request.isReady || store.isWorking || !store.tokenIsStored)

                if !store.tokenIsStored {
                    Text("Add your GitHub token once in Settings before the first use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Publish", systemImage: "arrow.up.circle")
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
                            Text("Your latest Sign & Publish job will appear here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }

                Section("Installer") {
                    Link(destination: URL(string: "https://nextsolution.cc/install/")!) {
                        Label("Open Next Solution Private Apps", systemImage: "safari")
                    }
                }
            }
            .navigationTitle("Activity")
        }
    }

    private func icon(for stage: SigningJob.Stage) -> String {
        switch stage {
        case .preparing: return "gearshape.2"
        case .uploading: return "arrow.up.circle"
        case .queued: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }
}

private struct NextSignerSettingsView: View {
    @ObservedObject var store: SignerStore
    @State private var revealToken = false

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub") {
                    TextField("Owner", text: $store.configuration.owner)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Repository", text: $store.configuration.repository)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Branch", text: $store.configuration.branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Workflow file", text: $store.configuration.workflowFile)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Fine-grained token") {
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
                        .foregroundColor(store.tokenIsStored ? .green : .gray)
                }

                Section("Required token permissions") {
                    Label("Contents: Read and write", systemImage: "doc.badge.gearshape")
                    Label("Actions: Read and write", systemImage: "bolt.horizontal.circle")
                    Text("Scope the token only to the NextSolution repository. The token is saved in the iOS Keychain, not UserDefaults.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Signing certificate") {
                    Text("The P12 certificate, password and provisioning profile stay in encrypted GitHub Actions secrets. After setup, Sign & Publish needs only the IPA.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .onDisappear { store.persistConfiguration() }
        }
    }
}

private struct UIKitDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Use the legacy UTI-based initializer deliberately. It is the most permissive
        // option on iOS 16 and works with IPA/TIPA files exposed by third-party file providers.
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

        init(parent: UIKitDocumentPicker) {
            self.parent = parent
        }

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
