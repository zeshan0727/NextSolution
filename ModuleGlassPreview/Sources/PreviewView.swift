import SwiftUI
import UIKit

struct RuntimeImageView: View {
    @ObservedObject var store: ModuleGlassStore
    let slot: ModuleSlot

    var body: some View {
        Group {
            if let image = store.image(for: slot.id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.white.opacity(0.20), Color.white.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .id("\(slot.id)-\(store.imageRevision.uuidString)")
    }
}

struct PreviewModuleTile: View {
    @ObservedObject var store: ModuleGlassStore
    let slot: ModuleSlot
    let height: CGFloat
    let cornerRadius: CGFloat
    var value: Double? = nil
    var compact = false

    var isSelected: Bool { store.selectedModuleID == slot.id }

    var body: some View {
        Button {
            store.selectedModuleID = slot.id
            store.record(.info, "Preview selected \(slot.id)")
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)

                RuntimeImageView(store: store, slot: slot)
                    .opacity(store.opacity)

                Color.black.opacity(0.09 + store.previewDim * 0.35)

                if slot.id == "connectivity" {
                    connectivityForeground
                } else if slot.id == "media" {
                    mediaForeground
                } else if slot.shape == .pill {
                    sliderForeground
                } else {
                    smallForeground
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.13), lineWidth: isSelected ? 2.2 : 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var connectivityForeground: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                circleIcon("airplane", active: false)
                circleIcon("antenna.radiowaves.left.and.right", active: true)
            }
            HStack(spacing: 12) {
                circleIcon("wifi", active: true)
                circleIcon("b.circle.fill", active: true)
            }
            Spacer(minLength: 0)
            Text("Connectivity")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(14)
    }

    private func circleIcon(_ symbol: String, active: Bool) -> some View {
        ZStack {
            Circle().fill(active ? Color.blue.opacity(0.90) : Color.white.opacity(0.14))
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 34, height: 34)
    }

    private var mediaForeground: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.black.opacity(0.25))
                    Image(systemName: "music.note")
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Now Playing")
                        .font(.caption.weight(.semibold))
                    Text("Module Glass")
                        .font(.caption2)
                        .opacity(0.75)
                }
                Spacer()
            }
            Spacer()
            HStack {
                Image(systemName: "backward.fill")
                Spacer()
                Image(systemName: "play.fill")
                    .font(.title3)
                Spacer()
                Image(systemName: "forward.fill")
            }
            .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(14)
    }

    private var sliderForeground: some View {
        VStack(spacing: 0) {
            if let value {
                Text("\(Int(value * 100))%")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .padding(.top, 12)
            }
            Spacer()
            Image(systemName: slot.symbol)
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 13)
        }
        .foregroundStyle(slot.id == "volume" && store.volumeIconColorEnabled ? Color(hex: store.volumeIconColor) : .white)
        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
    }

    private var smallForeground: some View {
        VStack(spacing: 7) {
            Image(systemName: slot.symbol)
                .font(.system(size: compact ? 18 : 21, weight: .semibold))
            if !compact {
                Text(slot.title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
        .padding(7)
    }
}

struct ControlCenterCanvas: View {
    @ObservedObject var store: ModuleGlassStore
    var immersive = false

    private let spacing: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let half = (width - spacing) / 2
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    PreviewModuleTile(store: store, slot: .slot("connectivity"), height: 138, cornerRadius: 28)
                        .frame(width: half)
                    PreviewModuleTile(store: store, slot: .slot("media"), height: 138, cornerRadius: 28)
                        .frame(width: half)
                }

                HStack(alignment: .top, spacing: spacing) {
                    PreviewModuleTile(store: store, slot: .slot("brightness"), height: 168, cornerRadius: 38, value: store.simulatedBrightness)
                        .frame(width: (width - spacing * 3) / 4)
                    PreviewModuleTile(store: store, slot: .slot("volume"), height: 168, cornerRadius: 38, value: store.simulatedVolume)
                        .frame(width: (width - spacing * 3) / 4)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: spacing) {
                        ForEach(["screenrecording", "screenmirroring", "orientation", "lowpower"], id: \.self) { id in
                            PreviewModuleTile(store: store, slot: .slot(id), height: 79, cornerRadius: 23, compact: true)
                        }
                    }
                    .frame(width: (width - spacing) / 2)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 4), spacing: spacing) {
                    ForEach(["focus", "flashlight", "timer", "calculator", "camera", "hearing", "notes", "home"], id: \.self) { id in
                        PreviewModuleTile(store: store, slot: .slot(id), height: 72, cornerRadius: 22, compact: true)
                    }
                }
            }
            .scaleEffect(store.previewScale)
            .frame(width: width, height: geo.size.height, alignment: .top)
        }
    }
}

struct PreviewView: View {
    @ObservedObject var store: ModuleGlassStore
    @State private var immersive = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("9:41")
                                .font(.caption.bold())
                            Spacer()
                            Image(systemName: "cellularbars")
                            Image(systemName: "wifi")
                            Image(systemName: "battery.100")
                        }
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 7)

                        ControlCenterCanvas(store: store)
                            .frame(height: 520)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 14)
                    }
                    .background(
                        ZStack {
                            LinearGradient(colors: [Color.indigo.opacity(0.78), Color.black.opacity(0.90)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Circle().fill(Color.blue.opacity(0.17)).blur(radius: 40).offset(x: 100, y: -130)
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .shadow(color: .black.opacity(0.22), radius: 16, y: 8)

                    selectedInspector
                    simulationControls
                }
                .padding()
            }
            .navigationTitle("Live Preview")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        immersive = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                }
            }
            .fullScreenCover(isPresented: $immersive) {
                ZStack {
                    LinearGradient(colors: [Color.indigo.opacity(0.82), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .ignoresSafeArea()
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                immersive = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding()
                        ControlCenterCanvas(store: store, immersive: true)
                            .padding()
                    }
                }
            }
        }
    }

    private var selectedInspector: some View {
        HStack(spacing: 14) {
            ZStack {
                RuntimeImageView(store: store, slot: store.selectedModule)
                Color.black.opacity(0.10)
                Image(systemName: store.selectedModule.symbol)
                    .foregroundStyle(.white)
                    .font(.title3.bold())
                    .shadow(radius: 2)
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(store.selectedModule.title)
                    .font(.headline)
                Text(store.selectedModule.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(store.selectedModule.id).jpg")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: store.image(for: store.selectedModule.id) == nil ? "photo.badge.plus" : "checkmark.circle.fill")
                .foregroundStyle(store.image(for: store.selectedModule.id) == nil ? Color.secondary : Color.green)
                .font(.title3)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var simulationControls: some View {
        VStack(spacing: 14) {
            previewSlider("Brightness", symbol: "sun.max.fill", value: $store.simulatedBrightness)
            previewSlider("Volume", symbol: "speaker.wave.2.fill", value: $store.simulatedVolume)
            previewSlider("Preview Dim", symbol: "circle.lefthalf.filled", value: $store.previewDim)
        }
        .padding(15)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func previewSlider(_ title: String, symbol: String, value: Binding<Double>) -> some View {
        VStack(spacing: 6) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1)
        }
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let r, g, b, a: UInt64
        switch clean.count {
        case 8:
            r = (value >> 24) & 0xFF
            g = (value >> 16) & 0xFF
            b = (value >> 8) & 0xFF
            a = value & 0xFF
        default:
            r = (value >> 16) & 0xFF
            g = (value >> 8) & 0xFF
            b = value & 0xFF
            a = 0xFF
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
