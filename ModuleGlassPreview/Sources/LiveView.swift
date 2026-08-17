import SwiftUI

struct LiveView: View {
    @ObservedObject var store: ModuleGlassStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    connectionCard
                    runtimeCard
                    volumeColorCard
                    actionCard
                    eventCard
                }
                .padding()
            }
            .navigationTitle("Device Live")
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Live Runtime Bridge").font(.headline)
                    Text("Writes directly to the installed Stable Recovery preference domain and image directory.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $store.deviceLive).labelsHidden()
            }
            Divider()
            Toggle(isOn: $store.continuousApply) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continuous Live Apply")
                    Text("Preference changes are sent as soon as you finish adjusting them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Label(store.deviceLive ? "Device writes enabled" : "Preview only", systemImage: store.deviceLive ? "bolt.horizontal.circle.fill" : "eye.circle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("Stable Recovery").font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Runtime Preferences", systemImage: "slider.horizontal.3").font(.headline)
            Toggle("Module backgrounds enabled", isOn: $store.enabled)
                .onChange(of: store.enabled) { _ in store.applyIfContinuous(reason: "Enabled changed") }
            Toggle("Remove Blur", isOn: $store.removeBlur)
                .onChange(of: store.removeBlur) { _ in store.applyIfContinuous(reason: "Remove Blur changed") }
            VStack(spacing: 7) {
                HStack {
                    Text("Background opacity")
                    Spacer()
                    Text("\(Int(store.opacity * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $store.opacity, in: 0...1, step: 0.01) { editing in
                    if !editing { store.applyIfContinuous(reason: "Opacity changed") }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text("Preference domain").font(.caption.weight(.semibold))
                Text("com.nextsolution.unlockvibrate").font(.caption2.monospaced()).foregroundStyle(.secondary)
                Text("Image directory").font(.caption.weight(.semibold)).padding(.top, 3)
                Text(ModuleGlassStore.backgroundDirectory)
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var volumeColorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Volume Foreground", systemImage: "speaker.wave.2.fill").font(.headline)
            Toggle("Custom icon + percentage color", isOn: $store.volumeIconColorEnabled)
                .onChange(of: store.volumeIconColorEnabled) { _ in store.applyIfContinuous(reason: "Volume color toggle changed") }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: store.normalizedHex(store.volumeIconColor)))
                    .frame(width: 44, height: 44)
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.secondary.opacity(0.25), lineWidth: 1) }
                TextField("#FFFFFF", text: $store.volumeIconColor)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled().font(.body.monospaced()).textFieldStyle(.roundedBorder)
                    .onSubmit {
                        store.volumeIconColor = store.normalizedHex(store.volumeIconColor)
                        store.applyIfContinuous(reason: "Volume color changed")
                    }
            }
            HStack(spacing: 8) {
                ForEach(["#FFFFFF", "#000000", "#00D4FF", "#FFD60A", "#FF375F"], id: \.self) { hex in
                    Button {
                        store.volumeIconColor = hex
                        store.applyIfContinuous(reason: "Volume color preset \(hex)")
                    } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 29, height: 29)
                            .overlay { Circle().stroke(.secondary.opacity(0.30), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var actionCard: some View {
        VStack(spacing: 10) {
            Button { store.applyPreferences(reason: "Apply Now") } label: {
                Label("Apply Now", systemImage: "bolt.fill").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            HStack(spacing: 10) {
                Button { store.loadPreferences() } label: {
                    Label("Reload", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Button { store.postReloadNotifications() } label: {
                    Label("Notify", systemImage: "bell.badge").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
            Text(store.status).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var eventCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Live Event Timeline", systemImage: "waveform.path.ecg").font(.headline)
                Spacer()
                Text("\(store.events.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if store.events.isEmpty {
                Text("No events yet").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(store.events.prefix(8)) { event in
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(levelColor(event.level)).frame(width: 7, height: 7).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.message).font(.caption)
                            Text(event.date.formatted(date: .omitted, time: .standard))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func levelColor(_ level: ConsoleEvent.Level) -> Color {
        switch level {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
