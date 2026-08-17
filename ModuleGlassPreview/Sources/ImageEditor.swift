import SwiftUI
import UIKit

struct ModuleImageEditor: View {
    let slot: ModuleSlot
    let image: UIImage
    let onSave: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: Double = 1.0
    @State private var horizontal: Double = 0.0
    @State private var vertical: Double = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(slot.title)
                            .font(.title2.bold())
                        Text("Prepare the JPEG before it is written to the Stable Recovery runtime. These crop controls do not create new tweak preference keys.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    GeometryReader { geo in
                        let frame = previewFrame(in: geo.size)
                        ZStack {
                            checkerboard
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .scaleEffect(zoom)
                                .offset(
                                    x: CGFloat(horizontal) * frame.width * 0.20,
                                    y: CGFloat(vertical) * frame.height * 0.20
                                )
                        }
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(RoundedRectangle(cornerRadius: previewRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: previewRadius, style: .continuous)
                                .stroke(.white.opacity(0.35), lineWidth: 1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 340)

                    control("Zoom", value: $zoom, range: 1.0...2.5, formatter: { String(format: "%.2fx", $0) })
                    control("Horizontal", value: $horizontal, range: -1.0...1.0, formatter: { String(format: "%+.0f%%", $0 * 100) })
                    control("Vertical", value: $vertical, range: -1.0...1.0, formatter: { String(format: "%+.0f%%", $0 * 100) })

                    HStack {
                        Button("Reset") {
                            zoom = 1
                            horizontal = 0
                            vertical = 0
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Text("Export \(Int(slot.shape.exportSize.width))×\(Int(slot.shape.exportSize.height))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Image Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply Live") {
                        let rendered = renderOutput()
                        onSave(rendered)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var checkerboard: some View {
        ZStack {
            Color.black.opacity(0.75)
            LinearGradient(
                colors: [.white.opacity(0.08), .clear, .white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var previewRadius: CGFloat {
        switch slot.shape {
        case .wide: return 30
        case .pill: return 48
        case .small: return 25
        }
    }

    private func previewFrame(in available: CGSize) -> CGSize {
        let maxW = max(160, available.width - 24)
        let maxH = max(180, available.height - 24)
        let ratio = slot.shape.aspectRatio
        if maxW / maxH > ratio {
            return CGSize(width: maxH * ratio, height: maxH)
        } else {
            return CGSize(width: maxW, height: maxW / ratio)
        }
    }

    @ViewBuilder
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, formatter: @escaping (Double) -> String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(formatter(value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func renderOutput() -> UIImage {
        let target = slot.shape.exportSize
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: target))

            let source = image.size
            guard source.width > 0, source.height > 0 else { return }
            let baseScale = max(target.width / source.width, target.height / source.height)
            let totalScale = baseScale * CGFloat(zoom)
            let drawSize = CGSize(width: source.width * totalScale, height: source.height * totalScale)
            let maxX = max(0, (drawSize.width - target.width) / 2)
            let maxY = max(0, (drawSize.height - target.height) / 2)
            let centerX = (target.width - drawSize.width) / 2
            let centerY = (target.height - drawSize.height) / 2
            let rect = CGRect(
                x: centerX + CGFloat(horizontal) * maxX,
                y: centerY + CGFloat(vertical) * maxY,
                width: drawSize.width,
                height: drawSize.height
            )
            image.draw(in: rect)
        }
    }
}
