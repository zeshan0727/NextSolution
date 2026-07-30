import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - App routing

enum NextPDFTab: Hashable {
    case library
    case editor
}

@MainActor
final class PDFAppRouter: ObservableObject {
    @Published var selectedTab: NextPDFTab = .library
    @Published var pendingOpenURL: URL?
    @Published var openRequestID = UUID()

    func edit(_ url: URL) {
        pendingOpenURL = url
        openRequestID = UUID()
        selectedTab = .editor
    }

    func consumePendingOpenURL() -> URL? {
        defer { pendingOpenURL = nil }
        return pendingOpenURL
    }
}

struct NextPDFRootView: View {
    @StateObject private var router = PDFAppRouter()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            PDFLibraryView(router: router)
                .tabItem {
                    Label("Library", systemImage: "folder.fill")
                }
                .tag(NextPDFTab.library)

            RobustPDFWorkspaceView(router: router)
                .tabItem {
                    Label("Editor", systemImage: "square.and.pencil")
                }
                .tag(NextPDFTab.editor)
        }
    }
}

// MARK: - Library model

struct PDFLibraryItem: Identifiable, Hashable {
    let url: URL
    let modifiedAt: Date
    let fileSize: Int64
    let folderName: String

    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var filename: String { url.lastPathComponent }
}

@MainActor
final class PDFLibraryStore: ObservableObject {
    @Published private(set) var items: [PDFLibraryItem] = []
    @Published var errorMessage: String?
    @Published var isImporting = false

    private let fileManager = FileManager.default

    init() {
        reload()
    }

    func reload() {
        do {
            let folders = try managedFolders(createPrimary: true)
            var discovered: [PDFLibraryItem] = []

            for folder in folders where fileManager.fileExists(atPath: folder.path) {
                let urls = try fileManager.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )

                for url in urls where url.pathExtension.lowercased() == "pdf" {
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
                    guard values?.isRegularFile != false else { continue }
                    discovered.append(
                        PDFLibraryItem(
                            url: url,
                            modifiedAt: values?.contentModificationDate ?? .distantPast,
                            fileSize: Int64(values?.fileSize ?? 0),
                            folderName: folder.lastPathComponent
                        )
                    )
                }
            }

            items = discovered.sorted { $0.modifiedAt > $1.modifiedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importPDF(from pickedURL: URL) {
        guard !isImporting else { return }
        isImporting = true

        Task {
            defer { isImporting = false }
            do {
                _ = try await Self.copyIntoLibrary(pickedURL)
                reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func delete(_ item: PDFLibraryItem) {
        do {
            try fileManager.removeItem(at: item.url)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ item: PDFLibraryItem, to proposedName: String) {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let safeName = trimmed.replacingOccurrences(of: "/", with: "-")
        let destination = item.url.deletingLastPathComponent()
            .appendingPathComponent(safeName)
            .appendingPathExtension("pdf")

        do {
            guard destination != item.url else { return }
            if fileManager.fileExists(atPath: destination.path) {
                throw PDFLibraryError.fileAlreadyExists
            }
            try fileManager.moveItem(at: item.url, to: destination)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func managedFolders(createPrimary: Bool) throws -> [URL] {
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let primary = documents.appendingPathComponent("PDF Library", isDirectory: true)
        if createPrimary {
            try fileManager.createDirectory(at: primary, withIntermediateDirectories: true)
        }
        return [
            primary,
            documents.appendingPathComponent("Saved PDFs", isDirectory: true),
            documents.appendingPathComponent("Imported PDFs", isDirectory: true)
        ]
    }

    nonisolated private static func copyIntoLibrary(_ sourceURL: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { sourceURL.stopAccessingSecurityScopedResource() }
            }

            let documents = try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let library = documents.appendingPathComponent("PDF Library", isDirectory: true)
            try fileManager.createDirectory(at: library, withIntermediateDirectories: true)

            let originalBase = sourceURL.deletingPathExtension().lastPathComponent
            let base = originalBase.isEmpty ? "Imported PDF" : originalBase
            var destination = library.appendingPathComponent(base).appendingPathExtension("pdf")
            var suffix = 2
            while fileManager.fileExists(atPath: destination.path) {
                destination = library.appendingPathComponent("\(base) \(suffix)").appendingPathExtension("pdf")
                suffix += 1
            }

            // Import only copies bytes into local app storage. No PDFKit parsing,
            // text extraction or OCR is performed here.
            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        }.value
    }
}

private enum PDFLibraryError: LocalizedError {
    case fileAlreadyExists

    var errorDescription: String? {
        switch self {
        case .fileAlreadyExists:
            return "A PDF with that name already exists in this folder."
        }
    }
}

// MARK: - Library UI

struct PDFLibraryView: View {
    @ObservedObject var router: PDFAppRouter
    @StateObject private var store = PDFLibraryStore()

    @State private var showingImporter = false
    @State private var searchText = ""
    @State private var shareItem: PDFLibraryShareItem?
    @State private var renameItem: PDFLibraryItem?
    @State private var renameText = ""

    private var filteredItems: [PDFLibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.items }
        return store.items.filter {
            $0.filename.localizedCaseInsensitiveContains(query) ||
            $0.folderName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            OCRStatusCard()
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }

                        Section("Your PDFs") {
                            ForEach(filteredItems) { item in
                                PDFLibraryRow(item: item) {
                                    router.edit(item.url)
                                } onShare: {
                                    shareItem = PDFLibraryShareItem(url: item.url)
                                }
                                .contextMenu {
                                    Button {
                                        router.edit(item.url)
                                    } label: {
                                        Label("Edit PDF", systemImage: "square.and.pencil")
                                    }

                                    Button {
                                        shareItem = PDFLibraryShareItem(url: item.url)
                                    } label: {
                                        Label("Export or Share", systemImage: "square.and.arrow.up")
                                    }

                                    Button {
                                        renameItem = item
                                        renameText = item.name
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        store.delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        shareItem = PDFLibraryShareItem(url: item.url)
                                    } label: {
                                        Label("Export", systemImage: "square.and.arrow.up")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("PDF Library")
            .searchable(text: $searchText, prompt: "Search PDFs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.reload()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                    .disabled(store.isImporting)
                }
            }
            .overlay(alignment: .top) {
                if store.isImporting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Saving PDF to local library…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8)
                    .padding(.top, 8)
                }
            }
            .fullScreenCover(isPresented: $showingImporter) {
                PDFLibraryDocumentPicker(
                    onPick: { url in
                        showingImporter = false
                        store.importPDF(from: url)
                    },
                    onCancel: {
                        showingImporter = false
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $shareItem) { item in
                PDFLibraryShareSheet(activityItems: [item.url])
            }
            .alert("Rename PDF", isPresented: Binding(
                get: { renameItem != nil },
                set: { if !$0 { renameItem = nil } }
            )) {
                TextField("File name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    renameItem = nil
                }
                Button("Rename") {
                    if let item = renameItem {
                        store.rename(item, to: renameText)
                    }
                    renameItem = nil
                }
            } message: {
                Text("Enter a new name. The .pdf extension is added automatically.")
            }
            .alert("PDF Library", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    store.errorMessage = nil
                }
            } message: {
                Text(store.errorMessage ?? "Unknown error")
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 70, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.blue, .secondary)

                VStack(spacing: 8) {
                    Text("Your PDF Library")
                        .font(.largeTitle.bold())
                    Text("Import a PDF once, keep it inside Next PDF, and open it for editing without using the external file picker again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("Import PDF", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isImporting)

                OCRStatusCard()
            }
            .padding(24)
        }
    }
}

private struct OCRStatusCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.viewfinder")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("OCR: Manual only")
                        .font(.headline)
                    Spacer()
                    Text("OFF")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
                Text("Importing and opening normal PDFs never runs OCR automatically. OCR can be added later as a separate button for scanned documents only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PDFLibraryRow: View {
    let item: PDFLibraryItem
    let onEdit: () -> Void
    let onShare: () -> Void

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.filename)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 7) {
                        Text(item.folderName)
                        Text("•")
                        Text(Self.byteFormatter.string(fromByteCount: item.fileSize))
                        Text("•")
                        Text(item.modifiedAt, style: .date)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Export or share")

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PDFLibraryShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PDFLibraryShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

private struct PDFLibraryDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        private let onCancel: () -> Void
        private var finished = false

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !finished, let url = urls.first else { return }
            finished = true
            DispatchQueue.main.async {
                self.onPick(url)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !finished else { return }
            finished = true
            DispatchQueue.main.async {
                self.onCancel()
            }
        }
    }
}
