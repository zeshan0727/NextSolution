import SwiftUI
import UIKit
import CoreFoundation

private struct ModuleSlot: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let shape: SlotShape
}

private enum SlotShape {
    case wide
    case pill
    case small
}

private let moduleSlots: [ModuleSlot] = [
    .init(id: "connectivity", title: "Connectivity", symbol: "antenna.radiowaves.left.and.right", shape: .wide),
    .init(id: "media", title: "Now Playing", symbol: "play.fill", shape: .wide),
    .init(id: "brightness", title: "Brightness", symbol: "sun.max.fill", shape: .pill),
    .init(id: "volume", title: "Volume", symbol: "speaker.wave.2.fill", shape: .pill),
    .init(id: "screenrecording", title: "Screen Recording", symbol: "record.circle", shape: .small),
    .init(id: "screenmirroring", title: "Screen Mirroring", symbol: "rectangle.on.rectangle", shape: .small),
    .init(id: "orientation", title: "Orientation Lock", symbol: "lock.rotation", shape: .small),
    .init(id: "lowpower", title: "Low Power", symbol: "battery.25", shape: .small),
    .init(id: "focus", title: "Focus", symbol: "moon.fill", shape: .small),
    .init(id: "flashlight", title: "Flashlight", symbol: "flashlight.on.fill", shape: .small),
    .init(id: "timer", title: "Timer", symbol: "timer", shape: .small),
    .init(id: "calculator", title: "Calculator", symbol: "plus.forwardslash.minus", shape: .small),
    .init(id: "camera", title: "Camera", symbol: "camera.fill", shape: .small),
    .init(id: "hearing", title: "Hearing", symbol: "ear", shape: .small),
    .init(id: "notes", title: "Quick Note", symbol: "note.text", shape: .small),
    .init(id: "home", title: "Home", symbol: "house.fill", shape: .small)
]

@MainActor
private final class ModuleGlassStore: ObservableObject {
    static let prefsDomain = "com.nextsolution.unlockvibrate" as CFString
    static let backgroundDirectory = "/var/mobile/Library/Preferences/NextSolutionTweaks/CCBackgrounds"
    static let logPath = "/var/mobile/Library/Logs/NextSolution/module-glass.log"

    @Published var deviceLive = true
    @Published var enabled = true
    @Published var opacity = 1.0
    @Published var removeBlur = false
    @Published var volumeIconColorEnabled = false
    @Published var volumeIconColor = "#FFFFFF"
    @Published var selectedSlot: ModuleSlot = moduleSlots[0]
    @Published var status = "Ready"
    @Published var refreshToken = UUID()

    init() {
        loadPreferences()
    }

    func loadPreferences() {
        CFPreferencesAppSynchronize(Self.prefsDomain)
        enabled = boolValue("CCModuleBackgroundsEnabled", fallback: true)
        opacity = min(1, max(0, doubleValue("CCModuleBackgroundOpacity", fallback: 1)))
        removeBlur = boolValue("CCModuleRemoveBlur", fallback: false)
        volumeIconColorEnabled = boolValue("CCModuleVolumeIconColorEnabled", fallback: false)
        volumeIconColor = stringValue("CCModuleVolumeIconColor", fallback: "#FFFFFF")
        refreshToken = UUID()
        status = "Loaded live Module Glass preferences"
    }

    func applyPreferences() {
        guard deviceLive else {
            status = "Preview only — Device Live is off"
            return
        }
        CFPreferencesSetAppValue("CCModuleBackgroundsEnabled" as CFString, NSNumber(value: enabled), Self.prefsDomain)
        CFPreferencesSetAppValue("CCModuleBackgroundOpacity" as CFString, NSNumber(value: opacity), Self.prefsDomain)
        CFPreferencesSetAppValue("CCModuleRemoveBlur" as CFString, NSNumber(value: removeBlur), Self.prefsDomain)
        CFPreferencesSetAppValue("CCModuleVolumeIconColorEnabled" as CFString, NSNumber(value: volumeIconColorEnabled), Self.prefsDomain)
        CFPreferencesSetAppValue("CCModuleVolumeIconColor" as CFString, normalizedHex(volumeIconColor) as CFString, Self.prefsDomain)
        CFPreferencesAppSynchronize(Self.prefsDomain)
        postReload()
        status = "Applied to Module Glass"
    }

    func image(for slot: ModuleSlot) -> UIImage? {
        UIImage(contentsOfFile: imagePath(slot.id))
    }

    func setImage(_ image: UIImage, for slot: ModuleSlot) {
        guard deviceLive else {
            status = "Turn on Device Live to write the image"
            return
        }
        do {
            try FileManager.default.createDirectory(atPath: Self.backgroundDirectory, withIntermediateDirectories: true)
            guard let data = image.jpegData(compressionQuality: 0.94) else {
                status = "Could not encode the selected image"
                return
            }
            try data.write(to: URL(fileURLWithPath: imagePath(slot.id)), options: .atomic)
            postReload()
            refreshToken = UUID()
            status = "Updated \(slot.title) background"
        } catch {
            status = "Write failed: \(error.localizedDescription)"
        }
    }

    func removeImage(for slot: ModuleSlot) {
        guard deviceLive else {
            status = "Turn on Device Live to remove the image"
            return
        }
        do {
            let path = imagePath(slot.id)
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
            postReload()
            refreshToken = UUID()
            status = "Removed \(slot.title) background"
        } catch {
            status = "Remove failed: \(error.localizedDescription)"
        }
    }

    func logText() -> String {
        (try? String(contentsOfFile: Self.logPath, encoding: .utf8)) ?? "No Module Glass log is available yet."
    }

    func postReload() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(rawValue: "com.nextsolution.unlockvibrate/preferences.changed" as CFString),
            nil,
            nil,
            true
        )
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(rawValue: "preferences.changed" as CFString),
            nil,
            nil,
            true
        )
    }

    private func imagePath(_ slot: String) -> String {
        "\(Self.backgroundDirectory)/\(slot).jpg"
    }

    private func boolValue(_ key: String, fallback: Bool) -> Bool {
        guard let raw = CFPreferencesCopyAppValue(key as CFString, Self.prefsDomain) else { return fallback }
        if let number = raw as? NSNumber { return number.boolValue }
        return fallback
    }

    private func doubleValue(_ key: String, fallback: Double) -> Double {
        guard let raw = CFPreferencesCopyAppValue(key as CFString, Self.prefsDomain) else { return fallback }
        if let number = raw as? NSNumber { return number.doubleValue }
        return fallback
    }

    private func stringValue(_ key: String, fallback: String) -> String {
        guard let raw = CFPreferencesCopyAppValue(key as CFString, Self.prefsDomain) else { return fallback }
        return (raw as? String) ?? fallback
    }

    private func normalizedHex(_ input: String) -> String {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let body = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEF")
        let filtered = String(body.unicodeScalars.filter { allowed.contains($0) })
        if filtered.count == 6 || filtered.count == 8 { return "#\(filtered)" }
        return "#FFFFFF"
    }
}

private struct SlotBackground: View {
    let slot: ModuleSlot
    @ObservedObject var store: ModuleGlassStore

    var body: some View {
        Group {
            if let image = store.image(for: slot) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .id(store.refreshToken)
    }
}

private struct ControlCenterPreview: View {
    @ObservedObject var store: ModuleGlassStore

    private func slot(_ id: String) -> ModuleSlot {
        moduleSlots.first(where: { $0.id == id }) ?? moduleSlots[0]
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                previewTile(slot("connectivity"), width: nil, height: 132, radius: 28)
                previewTile(slot("media"), width: nil, height: 132, radius: 28)
            }
            HStack(spacing: 10) {
                previewTile(slot("brightness"), width: nil, height: 150, radius: 38)
                previewTile(slot("volume"), width: nil, height: 150, radius: 38)
                VStack(spacing: 10) {
                    previewTile(slot("screenrecording"), width: nil, height: 70, radius: 23)
                    previewTile(slot("screenmirroring"), width: nil, height: 70, radius: 23)
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    @ViewBuilder
    private func previewTile(_ slot: ModuleSlot, width: CGFloat?, height: CGFloat, radius: CGFloat) -> some View {
        ZStack {
            SlotBackground(slot: slot, store: store)
            Color.black.opacity(0.12)
            VStack(spacing: 6) {
                Image(systemName: slot.symbol)
                    .font(.system(size: slot.shape == .small ? 20 : 24, weight: .semibold))
                if slot.shape != .small {
                    Text(slot.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .shadow(radius: 2)
        }
        .frame(maxWidth: width == nil ? .infinity : width, minHeight: height, maxHeight: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .opacity(store.opacity)
    }
}

private struct ModuleRow: View {
    let slot: ModuleSlot
    @ObservedObject var store: ModuleGlassStore
    let choose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: slot.shape == .pill ? 18 : 13, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                SlotBackground(slot: slot, store: store)
                    .clipShape(RoundedRectangle(cornerRadius: slot.shape == .pill ? 18 : 13, style: .continuous))
                Image(systemName: slot.symbol)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .frame(width: slot.shape == .wide ? 72 : 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title).font(.body.weight(.semibold))
                Text("\(slot.id).jpg").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Choose Image", action: choose)
                Button("Remove Image", role: .destructive) { store.removeImage(for: slot) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ImagePicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            if let image { parent.onPick(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private struct LogView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Module Glass Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ContentView: View {
    @StateObject private var store = ModuleGlassStore()
    @State private var showingPicker = false
    @State private var showingLog = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    ControlCenterPreview(store: store)

                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Device Live")
                                    .font(.headline)
                                Text("Writes directly to the installed Module Glass tweak")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $store.deviceLive)
                                .labelsHidden()
                        }

                        Divider()
                        Toggle("Module backgrounds", isOn: $store.enabled)
                            .onChange(of: store.enabled) { _ in store.applyPreferences() }
                        Toggle("Remove blur preference", isOn: $store.removeBlur)
                            .onChange(of: store.removeBlur) { _ in store.applyPreferences() }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Background opacity")
                                Spacer()
                                Text("\(Int(store.opacity * 100))%")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $store.opacity, in: 0...1, step: 0.01) { editing in
                                if !editing { store.applyPreferences() }
                            }
                        }

                        Divider()
                        Toggle("Volume icon + percentage color", isOn: $store.volumeIconColorEnabled)
                            .onChange(of: store.volumeIconColorEnabled) { _ in store.applyPreferences() }
                        HStack {
                            Text("Volume color")
                            Spacer()
                            TextField("#FFFFFF", text: $store.volumeIconColor)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled(true)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                                .onSubmit { store.applyPreferences() }
                        }
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Module Images")
                            .font(.title3.bold())
                        ForEach(moduleSlots) { slot in
                            ModuleRow(slot: slot, store: store) {
                                store.selectedSlot = slot
                                showingPicker = true
                            }
                            if slot.id != moduleSlots.last?.id { Divider() }
                        }
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(spacing: 10) {
                        Button {
                            store.loadPreferences()
                        } label: {
                            Label("Reload Device Preferences", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            store.postReload()
                            store.status = "Reload notification sent"
                        } label: {
                            Label("Live Apply Now", systemImage: "bolt.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showingLog = true
                        } label: {
                            Label("Open Module Glass Log", systemImage: "doc.text.magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(store.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Prefs: com.nextsolution.unlockvibrate\nImages: /var/mobile/Library/Preferences/NextSolutionTweaks/CCBackgrounds")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Module Glass Preview")
            .sheet(isPresented: $showingPicker) {
                ImagePicker { image in store.setImage(image, for: store.selectedSlot) }
            }
            .sheet(isPresented: $showingLog) {
                LogView(text: store.logText())
            }
        }
        .navigationViewStyle(.stack)
    }
}

@main
struct ModuleGlassPreviewApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
