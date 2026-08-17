import SwiftUI

struct CollectorView: View {
    @ObservedObject var store: ModuleGlassStore
    @ObservedObject var tester: ModuleGlassAutoTester
    @State private var showingReport = false
    @State private var showingJSON = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    introCard
                    runCard
                    resultSummary
                    if !tester.results.isEmpty { moduleResults }
                    uploadCard
                    localFilesCard
                    instructionsCard
                }
                .padding()
            }
            .navigationTitle("Log Collector")
            .sheet(isPresented: $showingReport) {
                AutoTestTextSheet(title: "Auto-Test Log", text: tester.reportText)
            }
            .sheet(isPresented: $showingJSON) {
                AutoTestTextSheet(title: "Auto-Test JSON", text: tester.reportJSON)
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic Module Test")
                        .font(.headline)
                    Text("Stable Recovery runtime logger")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("1.1.1")
                    .font(.caption.bold().monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            }

            Text("One tap enables Module Glass verbose diagnostics, refreshes the runtime, checks every module image, parses the actual SpringBoard log, runs deep diagnostics, and builds one session report for inspection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var runCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Test Session", systemImage: "play.circle.fill")
                    .font(.headline)
                Spacer()
                if tester.running { ProgressView().controlSize(.small) }
            }

            ProgressView(value: tester.progress)
                .animation(nil, value: tester.progress)

            HStack {
                Text(tester.phase)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tester.controlCenterNeeded ? .orange : .secondary)
                Spacer()
                Text("\(Int(tester.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if tester.controlCenterNeeded {
                Label("Open Control Center now. Keep it visible for 2–3 seconds, then return here. The collector will continue automatically.", systemImage: "hand.draw.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button {
                Task { await tester.run(store: store) }
            } label: {
                HStack {
                    Image(systemName: tester.running ? "hourglass" : "bolt.horizontal.circle.fill")
                    Text(tester.running ? "Auto Test Running…" : "Run Full Auto Test")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .disabled(tester.running)

            if !tester.running && !tester.results.isEmpty {
                Button(role: .destructive) { tester.clear() } label: {
                    Label("Clear Current Session", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var resultSummary: some View {
        if !tester.results.isEmpty {
            let pass = tester.results.filter { $0.state == .pass }.count
            let native = tester.results.filter { $0.state == .native }.count
            let warn = tester.results.filter { $0.state == .warning || $0.state == .notObserved }.count
            let fail = tester.results.filter { $0.state == .fail }.count

            VStack(alignment: .leading, spacing: 12) {
                Label("Session Summary", systemImage: "chart.bar.doc.horizontal.fill")
                    .font(.headline)
                HStack(spacing: 8) {
                    summaryPill("PASS", pass, .green)
                    summaryPill("NATIVE", native, .secondary)
                    summaryPill("WARN", warn, .orange)
                    summaryPill("FAIL", fail, .red)
                }
                HStack {
                    Label("Controllers", systemImage: "square.stack.3d.up")
                    Spacer()
                    Text("\(tester.controllersSeen)").monospacedDigit()
                }
                HStack {
                    Label("Runtime lines", systemImage: "text.alignleft")
                    Spacer()
                    Text("\(tester.runtimeLinesCaptured)").monospacedDigit()
                }
            }
            .font(.caption)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func summaryPill(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var moduleResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Module-by-Module Results", systemImage: "square.grid.3x3.fill")
                .font(.headline)
                .padding(.bottom, 10)

            ForEach(tester.results) { result in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: result.state.systemImage)
                        .foregroundStyle(result.state.color)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(result.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(result.state.rawValue)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(result.state.color)
                        }
                        Text(result.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let strategy = result.runtimeStrategy {
                            Text("strategy: \(strategy)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 9)
                if result.id != tester.results.last?.id { Divider() }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var uploadCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Automatic Log Share", systemImage: "icloud.and.arrow.up.fill")
                .font(.headline)

            Toggle("Auto-upload when test finishes", isOn: $tester.autoUploadWhenTokenAvailable)
                .font(.subheadline)

            Text("If a GitHub token is saved, the completed .log and .json are uploaded automatically to transfer/uploads/moduleglass/autotest/. The token is kept in Keychain and is never included in the report.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("GitHub Personal Access Token", text: $store.githubToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 9) {
                Button("Save Token") { store.saveGitHubToken() }
                    .buttonStyle(.bordered)
                Button("Remove", role: .destructive) { store.clearGitHubToken() }
                    .buttonStyle(.bordered)
                Spacer()
            }

            if !tester.reportText.isEmpty && tester.uploadedTextPath == nil {
                Button {
                    Task { await tester.upload(store: store) }
                } label: {
                    Label("Upload Current Auto-Test Log", systemImage: "arrow.up.doc.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let path = tester.uploadedTextPath {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Uploaded successfully", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.caption.bold())
                    Text(path)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                    Text("Now tell ChatGPT: check log")
                        .font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var localFilesCard: some View {
        if !tester.reportText.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                Label("Collected Files", systemImage: "doc.badge.gearshape")
                    .font(.headline)

                if let path = tester.localLogPath {
                    pathRow("LOG", path)
                }
                if let path = tester.localJSONPath {
                    pathRow("JSON", path)
                }

                HStack(spacing: 9) {
                    Button { showingReport = true } label: {
                        Label("View Log", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { showingJSON = true } label: {
                        Label("View JSON", systemImage: "curlybraces")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let path = tester.localLogPath {
                    ShareLink(item: URL(fileURLWithPath: path)) {
                        Label("Share Auto-Test Log", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func pathRow(_ label: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.bold())
            Text(path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How the automatic test works", systemImage: "info.circle.fill")
                .font(.headline)
            Text("1. Press Run Full Auto Test.\n2. If prompted, open Control Center once for 2–3 seconds and return.\n3. The app tests every known Module Glass slot against the actual SpringBoard runtime log.\n4. The full log is saved automatically and uploaded automatically when a token is configured.\n5. Tell ChatGPT “check log” and the newest auto-test upload can be inspected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct AutoTestTextSheet: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text.isEmpty ? "No test report generated yet." : text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
