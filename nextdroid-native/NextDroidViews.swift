@MainActor
struct NextDroidRootView: View {
    let data: UTMData
    @StateObject private var installer = NextDroidInstaller()
    @State private var isEngineVisible = false
    @State private var isStarting = false

    var body: some View {
        Group {
            if isEngineVisible {
                UTMSingleWindowView(data: data)
            } else {
                NextDroidSetupView(
                    installer: installer,
                    isStarting: isStarting,
                    startAndroid: startAndroid,
                    openManager: { isEngineVisible = true }
                )
            }
        }
    }

    private func startAndroid() {
        guard !isStarting else { return }
        isStarting = true
        Task {
            await data.listRefresh()
            guard let vm = data.virtualMachines.first(where: {
                $0.pathUrl.lastPathComponent == NextDroidVMConfiguration.directoryName
            }) else {
                installer.reportStartFailure("The Android VM configuration could not be loaded.")
                isStarting = false
                return
            }
            data.run(vm: vm)
            isEngineVisible = true
            isStarting = false
        }
    }
}

struct NextDroidSetupView: View {
    @ObservedObject var installer: NextDroidInstaller
    let isStarting: Bool
    let startAndroid: () -> Void
    let openManager: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    hero
                    statusCard
                    actionArea
                    requirements
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("NextDroid")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.95), .cyan.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 104, height: 104)
                Image(systemName: "apps.iphone")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.78))
            }
            Text("Android 11 on iPhone")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("Bliss OS with OpenGApps and persistent storage, powered by the native UTM/QEMU engine.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                statusIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if installer.phase == .downloading {
                ProgressView(value: installer.progress)
                    .tint(.green)
                HStack {
                    Text(byteProgress)
                    Spacer()
                    Text("\(Int(installer.progress * 100))%")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else if installer.phase == .verifying || installer.phase == .installing {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var actionArea: some View {
        switch installer.phase {
        case .idle:
            Button(action: installer.startDownload) {
                Label("Download Android 11", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NextDroidPrimaryButtonStyle())
        case .downloading:
            Button(role: .cancel, action: installer.cancelDownload) {
                Text("Cancel Download").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        case .verifying, .installing:
            Text("Keep NextDroid open until setup finishes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .ready:
            VStack(spacing: 12) {
                Button(action: startAndroid) {
                    HStack {
                        if isStarting { ProgressView().tint(.black) }
                        Label("Start Android 11", systemImage: "play.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(NextDroidPrimaryButtonStyle())
                .disabled(isStarting)

                Button("Open VM Manager", action: openManager)
                    .buttonStyle(.bordered)
            }
        case .failed:
            Button(action: installer.retry) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NextDroidPrimaryButtonStyle())
        }
    }

    private var requirements: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("One-time download: 2.09 GB", systemImage: "externaldrive")
            Label("Persistent Android disk: grows as used", systemImage: "internaldrive")
            Label("Designed for TrollStore on iOS 16", systemImage: "iphone")
            Label("Play Store is included through OpenGApps", systemImage: "bag")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch installer.phase {
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .downloading:
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.cyan)
        case .verifying, .installing:
            Image(systemName: "gearshape.2.fill").foregroundStyle(.cyan)
        case .idle:
            Image(systemName: "shippingbox.fill").foregroundStyle(.secondary)
        }
    }

    private var statusTitle: String {
        switch installer.phase {
        case .idle: return "Android is not installed"
        case .downloading: return "Downloading Android 11"
        case .verifying: return "Verifying Android image"
        case .installing: return "Creating Android VM"
        case .ready: return "Android 11 is ready"
        case .failed: return "Setup failed"
        }
    }

    private var statusDetail: String {
        switch installer.phase {
        case .idle:
            return "The large system image will download inside the app."
        case .downloading:
            return "Keep the app open and connected to the internet."
        case .verifying:
            return "Checking the SHA-256 integrity before installation."
        case .installing:
            return "Preparing the persistent 16 GB sparse data disk."
        case .ready:
            return "Tap Start Android 11 to boot the virtual phone."
        case .failed(let message):
            return message
        }
    }

    private var byteProgress: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let downloaded = formatter.string(fromByteCount: installer.downloadedBytes)
        let expected = formatter.string(fromByteCount: installer.expectedBytes)
        return "\(downloaded) of \(expected)"
    }
}

private struct NextDroidPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(
                LinearGradient(
                    colors: [.green, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
