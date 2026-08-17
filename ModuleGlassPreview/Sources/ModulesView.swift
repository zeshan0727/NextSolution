import SwiftUI
import PhotosUI
import UIKit

private struct EditorPayload: Identifiable {
    let id = UUID()
    let slot: ModuleSlot
    let image: UIImage
}

private struct ModuleEditorCard: View {
    @ObservedObject var store: ModuleGlassStore
    let slot: ModuleSlot
    let onEdit: (ModuleSlot, UIImage) -> Void

    @State private var pickerItem: PhotosPickerItem?

    private var info: ModuleImageInfo { store.imageInfo(for: slot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RuntimeImageView(store: store, slot: slot)
                    Color.black.opacity(0.10)
                    Image(systemName: slot.symbol)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .frame(width: slot.shape == .wide ? 82 : 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: slot.shape == .pill ? 24 : 17, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(slot.title)
                        .font(.headline)
                    Text(slot.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(info.exists ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(info.exists ? "\(formatBytes(info.sizeBytes)) • \(info.width)×\(info.height)" : "No custom JPEG")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(info.exists ? "Replace" : "Choose Image", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if info.exists {
                    Button(role: .destructive) {
                        store.removeImage(for: slot)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text(info.path)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        await MainActor.run { store.record(.error, "Photo picker could not decode an image for \(slot.id)") }
                        return
                    }
                    await MainActor.run {
                        store.record(.info, "Opened image editor for \(slot.id)")
                        onEdit(slot, image)
                        pickerItem = nil
                    }
                } catch {
                    await MainActor.run {
                        store.record(.error, "Photo picker failed for \(slot.id): \(error.localizedDescription)")
                        pickerItem = nil
                    }
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct ModulesView: View {
    @ObservedObject var store: ModuleGlassStore
    @State private var editorPayload: EditorPayload?
    @State private var query = ""

    private var filtered: [ModuleSlot] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ModuleSlot.all }
        return ModuleSlot.all.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    statusHeader
                    ForEach(filtered) { slot in
                        ModuleEditorCard(store: store, slot: slot) { slot, image in
                            editorPayload = EditorPayload(slot: slot, image: image)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Module Editor")
            .searchable(text: $query, prompt: "Search modules")
            .sheet(item: $editorPayload) { payload in
                ModuleImageEditor(slot: payload.slot, image: payload.image) { rendered in
                    store.saveImage(rendered, for: payload.slot)
                }
            }
        }
    }

    private var statusHeader: some View {
        let present = ModuleSlot.all.filter { store.imageInfo(for: $0).exists }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stable Runtime Images")
                        .font(.headline)
                    Text("\(present) of \(ModuleSlot.all.count) modules have custom backgrounds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("Images are cropped and preprocessed in this app, then written using the exact filenames consumed by Module Glass Stable Recovery.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
