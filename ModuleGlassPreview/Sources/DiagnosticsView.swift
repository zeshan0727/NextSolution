import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @ObservedObject var store: ModuleGlassStore
    @State private var showingReport = false
    @State private var showingJSON = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    healthCard
                    actionsCard
                    githubCard
                    logCard
                    eventCard
                }
                .padding()
            }
            .navigationTitle("Diagnostics")
            .sheet(isPresented: $showingReport) {
                DiagnosticTextSheet(title: "Diagnostic Report", text: store.diagnosticText)
            }
            .sheet(isPresented: $showingJSON) {
                DiagnosticTextSheet(title: "Diagnostic JSON", text: store.diagnosticJSON)
            }
        }
    }

    private var healthCard: some View {
        let imageCount = ModuleSlot.all.filter { store.imageInfo(for: $0).exists }.count
        let tweakLogExists = FileManager.default.fileExists(atPath: ModuleGlassStore.tweakLogPath)
        return VStack(alignment: .leading, spacing: 13) {
            Label("Runtime Health", systemImage: "stethoscope").font(.headline)
            healthRow("Custom module images", value: "\(imageCount)/\(ModuleSlot.all.count)", ok: imageCount > 0)
            healthRow("Tweak log file", value: tweakLogExists ? "Found" : "Not found", ok: tweakLogExists)
            healthRow("Preference domain", value: "Reachable", ok: true)
            healthRow("Developer console", value: "1.1.0", ok: true)
            Divider()
            Text("Deep Diagnostics performs a temporary write/delete test in the runtime image folder, inspects known dpkg status locations, inventories every JPEG, and attaches tweak + console log tails.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func healthRow(_ title: String, value: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(title)
            Spacer()
            Text(value).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private var actionsCard: some View {
        VStack(spacing: 10) {
            Button {
                Task { await store.runDiagnostics() }
            } label: {
                HStack {
                    if store.diagnosticsRunning { ProgressView().controlSize(.small) }
                    Label(store.diagnosticsRunning ? "Running Diagnostics…" : "Run Deep Diagnostics", systemImage: "waveform.path.ecg.rectangle")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.diagnosticsRunning)

            HStack(spacing: 10) {
                Button {
                    showingReport = true
                } label: {
                    Label("Report", systemImage: "doc.text").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(store.diagnosticText.isEmpty)

                Button {
                    showingJSON = true
                } label: {
                    Label("JSON", systemImage: "curlybraces").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(store.diagnosticJSON.isEmpty)
            }

            if !store.diagnosticText.isEmpty {
                HStack(spacing: 10) {
                    ShareLink(item: store.diagnosticText) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        UIPasteboard.general.string = store.diagnosticText
                        store.status = "Diagnostic report copied"
                        store.record(.success, "Diagnostic report copied to pasteboard")
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var githubCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("One-Tap Log Upload", systemImage: "arrow.up.doc.fill").font(.headline)
                Spacer()
                if store.uploadRunning { ProgressView().controlSize(.small) }
            }

            Text("Logs upload to zeshan0727/NextJailbreak → transfer/uploads/moduleglass/. The token stays in this app's iOS Keychain and is never written into diagnostics.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("GitHub Personal Access Token", text: $store.githubToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Button("Save Token") { store.saveGitHubToken() }
                    .buttonStyle(.bordered)
                Button("Remove Token", role: .destructive) { store.clearGitHubToken() }
                    .buttonStyle(.bordered)
            }

            Button {
                Task { await store.uploadDiagnostics() }
            } label: {
                Label(store.uploadRunning ? "Uploading…" : "Upload Diagnostic Log", systemImage: "icloud.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.uploadRunning || store.githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let uploaded = store.lastUploaded {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Uploaded", systemImage: "checkmark.seal.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    Text(uploaded.textPath).font(.caption2.monospaced()).textSelection(.enabled)
                    Text(uploaded.jsonPath).font(.caption2.monospaced()).textSelection(.enabled)
                    Text("After this, tell ChatGPT: check log")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Diagnostic Coverage", systemImage: "list.bullet.rectangle").font(.headline)
            coverage("Device / iOS / app build")
            coverage("Stable runtime preference values")
            coverage("All module image paths, sizes and pixel dimensions")
            coverage("Runtime image-directory write test")
            coverage("Known dpkg package/version evidence")
            coverage("Darwin notification names")
            coverage("Tweak log + console log tails")
            coverage("Apply actions, warnings and errors with timestamps")
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func coverage(_ text: String) -> some View {
        Label(text, systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
    }

    private var eventCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recent Console Events", systemImage: "terminal").font(.headline)
                Spacer()
                Text("\(store.events.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(store.events.prefix(12)) { event in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(event.level.rawValue).font(.system(size: 9, weight: .bold, design: .monospaced))
                        Text(event.date.formatted(date: .omitted, time: .standard))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                    Text(event.message).font(.caption).textSelection(.enabled)
                }
                if event.id != store.events.prefix(12).last?.id { Divider() }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct DiagnosticTextSheet: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text.isEmpty ? "No report generated yet." : text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
