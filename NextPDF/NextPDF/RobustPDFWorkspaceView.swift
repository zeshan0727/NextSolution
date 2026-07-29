import SwiftUI
import UIKit
import PDFKit
import PencilKit
import UniformTypeIdentifiers

struct RobustPDFWorkspaceView: View {
    @StateObject private var model = PDFEditorModel()

    @State private var showingPicker = false
    @State private var showingExporter = false
    @State private var showingAddText = false
    @State private var showingDateEditor = false
    @State private var showingSignature = false
    @State private var showingDrawing = false
    @State private var showingPages = false
    @State private var showingSearch = false
    @State private var sidebarVisible = true
    @State private var isImporting = false
    @State private var importStatus = "Preparing PDF…"
    @State private var editDraft: TextEditDraft?
    @State private var shareItem: RobustShareItem?
    @State private var exportKind: PDFExportKind = .editable

    var body: some View {
        NavigationStack {
            ZStack {
                if let document = model.document {
                    editorLayout(document: document)
                } else {
                    emptyState
                }

                if isImporting {
                    loadingOverlay
                }
            }
            .navigationTitle(model.documentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .fullScreenCover(isPresented: $showingPicker) {
                RobustNativePDFPicker(
                    onPick: { url in
                        showingPicker = false
                        importPDF(from: url)
                    },
                    onCancel: {
                        showingPicker = false
                    }
                )
                .ignoresSafeArea()
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: model.exportDocument(kind: exportKind),
                contentType: .pdf,
                defaultFilename: model.exportFilename(kind: exportKind)
            ) { result in
                switch result {
                case .success:
                    model.presentMessage(
                        exportKind == .secureRasterized
                        ? "A secure flattened PDF copy was exported successfully."
                        : "The edited PDF was exported successfully."
                    )
                case .failure(let error):
                    model.present(error: error)
                }
            }
            .sheet(isPresented: $showingAddText) {
                AddTextSheet(fonts: model.availableFonts) { text, style in
                    model.addText(text, style: style)
                    showingAddText = false
                }
            }
            .sheet(item: $editDraft) { draft in
                ExistingTextEditSheet(draft: draft, fonts: model.availableFonts) { updatedText, style in
                    model.replaceText(draft: draft, with: updatedText, style: style)
                    editDraft = nil
                }
            }
            .sheet(isPresented: $showingDateEditor) {
                DateReplacementSheet(initialDate: Date()) { text, style in
                    guard let draft = model.makeTextEditDraft() else {
                        model.presentMessage("Select the existing date first, then tap Change Date again.")
                        showingDateEditor = false
                        return
                    }
                    model.replaceText(
                        draft: draft,
                        with: text,
                        style: style.mergingDetectedStyle(from: draft)
                    )
                    showingDateEditor = false
                }
            }
            .sheet(isPresented: $showingSignature) {
                InkDrawingSheet(title: "Add Signature", mode: .signature) { drawing, color, width in
                    model.addInkDrawing(drawing, color: color, lineWidth: width, mode: .signature)
                    showingSignature = false
                }
            }
            .sheet(isPresented: $showingDrawing) {
                InkDrawingSheet(title: "Draw on PDF", mode: .drawing) { drawing, color, width in
                    model.addInkDrawing(drawing, color: color, lineWidth: width, mode: .drawing)
                    showingDrawing = false
                }
            }
            .sheet(isPresented: $showingPages) {
                PageOrganizerSheet(model: model)
            }
            .sheet(isPresented: $showingSearch) {
                PDFSearchSheet(model: model)
            }
            .sheet(item: $shareItem) { item in
                RobustShareSheet(activityItems: [item.url])
            }
            .alert("Next PDF Pro", isPresented: $model.showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(model.alertMessage)
            }
        }
    }

    private func editorLayout(document: PDFDocument) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if sidebarVisible {
                    RobustEditorSidebar(
                        model: model,
                        onEditText: openExistingTextEditor,
                        onAddText: { showingAddText = true },
                        onDate: openDateEditor,
                        onSignature: { showingSignature = true },
                        onDraw: { showingDrawing = true },
                        onPages: { showingPages = true },
                        onSearch: { showingSearch = true },
                        onSave: { model.saveInsideApp(kind: .editable) },
                        onSecureSave: { model.saveInsideApp(kind: .secureRasterized) },
                        onExport: { kind in
                            exportKind = kind
                            showingExporter = true
                        },
                        onShare: share
                    )
                    .frame(width: sidebarWidth(for: geometry.size.width))
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    Divider()
                }

                PDFKitEditorView(document: document, model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))
            }
            .animation(.easeInOut(duration: 0.2), value: sidebarVisible)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editorStatusBar
                .background(.ultraThinMaterial)
        }
    }

    private func sidebarWidth(for totalWidth: CGFloat) -> CGFloat {
        if totalWidth >= 900 { return 225 }
        if totalWidth >= 650 { return 190 }
        return min(148, max(132, totalWidth * 0.35))
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 66, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.blue, .secondary)

                VStack(spacing: 8) {
                    Text("Next PDF Pro")
                        .font(.largeTitle.bold())
                    Text("Choose any PDF from Files. The full editing sidebar appears after it opens.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    showingPicker = true
                } label: {
                    Label("Choose PDF from Files", systemImage: "folder.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isImporting)

                VStack(alignment: .leading, spacing: 12) {
                    RobustFeatureRow(icon: "doc.badge.plus", title: "Compatible file picker", detail: "Accepts PDFs from iCloud, Drive, OneDrive and other Files providers.")
                    RobustFeatureRow(icon: "character.cursor.ibeam", title: "Edit existing text", detail: "Replace names, amounts, dates or remove selected text.")
                    RobustFeatureRow(icon: "signature", title: "Sign and draw", detail: "Add signatures, drawings, markup and shapes.")
                    RobustFeatureRow(icon: "sidebar.left", title: "Full editing sidebar", detail: "All tools appear immediately after the document opens.")
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(24)
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(importStatus)
                    .font(.headline)
                Text("The file is being copied safely into Next PDF.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 310)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 18)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                showingPicker = true
            } label: {
                Label("Open", systemImage: "folder")
            }
            .disabled(isImporting)

            if model.document != nil {
                Button {
                    sidebarVisible.toggle()
                } label: {
                    Label(sidebarVisible ? "Hide Tools" : "Show Tools", systemImage: "sidebar.left")
                }
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                model.saveInsideApp(kind: .editable)
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(model.document == nil || isImporting)

            Button {
                share(kind: .editable)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(model.document == nil || isImporting)
        }
    }

    private var editorStatusBar: some View {
        HStack(spacing: 10) {
            Label("Page \(model.currentPageNumber) of \(max(model.pageCount, 1))", systemImage: "doc")
                .font(.caption.weight(.semibold))

            Spacer(minLength: 8)

            if model.hasTextSelection {
                Label("Text selected", systemImage: "text.cursor")
                    .foregroundStyle(.blue)
                    .font(.caption.weight(.semibold))
            } else if model.hasSelectedAnnotation {
                Label(model.selectedAnnotationName, systemImage: "selection.pin.in.out")
                    .foregroundStyle(.blue)
                    .font(.caption.weight(.semibold))
            } else {
                Text("Long-press text to select it")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func importPDF(from selectedURL: URL) {
        guard !isImporting else { return }
        isImporting = true
        importStatus = "Reading selected file…"

        Task {
            defer { isImporting = false }

            do {
                let localURL = try await RobustPDFFileImporter.makeVerifiedLocalCopy(of: selectedURL)
                importStatus = "Opening PDF…"
                await Task.yield()
                model.open(url: localURL)
                sidebarVisible = true
            } catch {
                model.present(error: error)
            }
        }
    }

    private func openExistingTextEditor() {
        guard let draft = model.makeTextEditDraft() else {
            model.presentMessage("Select existing text first. Long-press a word or date, adjust the selection handles, then tap Edit Text.")
            return
        }
        editDraft = draft
    }

    private func openDateEditor() {
        guard model.makeTextEditDraft() != nil else {
            model.presentMessage("Select the existing date first, then tap Change Date.")
            return
        }
        showingDateEditor = true
    }

    private func share(kind: PDFExportKind) {
        if let url = model.makeShareFile(kind: kind) {
            shareItem = RobustShareItem(url: url)
        }
    }
}

private struct RobustEditorSidebar: View {
    @ObservedObject var model: PDFEditorModel
    let onEditText: () -> Void
    let onAddText: () -> Void
    let onDate: () -> Void
    let onSignature: () -> Void
    let onDraw: () -> Void
    let onPages: () -> Void
    let onSearch: () -> Void
    let onSave: () -> Void
    let onSecureSave: () -> Void
    let onExport: (PDFExportKind) -> Void
    let onShare: (PDFExportKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Edit Tools", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Text(model.hasTextSelection ? "Selected text is ready" : "Select text or choose a tool")
                        .font(.caption2)
                        .foregroundStyle(model.hasTextSelection ? .blue : .secondary)
                }

                RobustSidebarSection(title: "TEXT") {
                    RobustSidebarButton("Edit Text", icon: "character.cursor.ibeam", primary: true, action: onEditText)
                    RobustSidebarButton("Add Text", icon: "text.badge.plus", action: onAddText)
                    RobustSidebarButton("Change Date", icon: "calendar", action: onDate)
                    RobustSidebarButton("Remove Text", icon: "eraser") { model.removeSelectedText() }
                        .opacity(model.hasTextSelection ? 1 : 0.55)
                }

                RobustSidebarSection(title: "MARKUP") {
                    RobustSidebarButton("Highlight", icon: "highlighter") { model.markSelection(.highlight) }
                    RobustSidebarButton("Underline", icon: "underline") { model.markSelection(.underline) }
                    RobustSidebarButton("Strike Out", icon: "strikethrough") { model.markSelection(.strikeOut) }
                    RobustSidebarButton("Whiteout", icon: "rectangle.fill") { model.redactSelection(coverColor: .white) }
                    RobustSidebarButton("Redact", icon: "eye.slash.fill") { model.redactSelection(coverColor: .black) }
                }

                RobustSidebarSection(title: "SIGN & DRAW") {
                    RobustSidebarButton("Signature", icon: "signature", action: onSignature)
                    RobustSidebarButton("Draw", icon: "pencil.tip.crop.circle", action: onDraw)
                }

                RobustSidebarSection(title: "SHAPES") {
                    ForEach(PDFShapeKind.allCases) { shape in
                        RobustSidebarButton(shape.title, icon: shape.systemImage) {
                            model.addShape(shape)
                        }
                    }
                }

                RobustSidebarSection(title: "DOCUMENT") {
                    RobustSidebarButton("Pages", icon: "rectangle.stack", action: onPages)
                    RobustSidebarButton("Search", icon: "magnifyingglass", action: onSearch)
                    RobustSidebarButton("Undo", icon: "arrow.uturn.backward") { model.undo() }
                        .disabled(!model.canUndo)
                    RobustSidebarButton("Redo", icon: "arrow.uturn.forward") { model.redo() }
                        .disabled(!model.canRedo)
                    if model.hasSelectedAnnotation {
                        RobustSidebarButton("Delete Selected", icon: "trash", destructive: true) {
                            model.deleteSelectedAnnotation()
                        }
                    }
                }

                RobustSidebarSection(title: "SAVE & SHARE") {
                    RobustSidebarButton("Save", icon: "square.and.arrow.down", action: onSave)
                    RobustSidebarButton("Secure Save", icon: "lock.doc", action: onSecureSave)
                    RobustSidebarButton("Export", icon: "folder.badge.plus") { onExport(.editable) }
                    RobustSidebarButton("Secure Export", icon: "lock.square") { onExport(.secureRasterized) }
                    RobustSidebarButton("Share", icon: "square.and.arrow.up") { onShare(.editable) }
                    RobustSidebarButton("Secure Share", icon: "lock.open.display") { onShare(.secureRasterized) }
                }
            }
            .padding(10)
        }
        .background(.ultraThinMaterial)
    }
}

private struct RobustSidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 5)
            content
        }
    }
}

private struct RobustSidebarButton: View {
    let title: String
    let icon: String
    var primary = false
    var destructive = false
    let action: () -> Void

    init(_ title: String, icon: String, primary: Bool = false, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.primary = primary
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        if primary { return .white }
        if destructive { return .red }
        return .primary
    }

    private var backgroundColor: Color {
        primary ? .blue : Color.secondary.opacity(0.11)
    }
}

private struct RobustFeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RobustShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct RobustShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

private struct RobustNativePDFPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Some third-party Files providers incorrectly label PDFs as generic data.
        // Allow both types and verify the actual PDF header after selection.
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.pdf, .data],
            asCopy: true
        )
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

private enum RobustPDFFileImporter {
    static func makeVerifiedLocalCopy(of sourceURL: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let values = try? sourceURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                throw RobustPDFImportError.folderSelected
            }

            let data = try coordinatedRead(from: sourceURL)
            guard !data.isEmpty else {
                throw RobustPDFImportError.emptyFile
            }

            let headerLength = min(data.count, 1024)
            let header = data.prefix(headerLength)
            guard header.range(of: Data("%PDF-".utf8)) != nil else {
                throw RobustPDFImportError.notPDF
            }

            guard PDFDocument(data: data) != nil else {
                throw RobustPDFImportError.unreadablePDF
            }

            let fileManager = FileManager.default
            let documents = try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let folder = documents.appendingPathComponent("Imported PDFs", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

            let baseName = sourceURL.deletingPathExtension().lastPathComponent
            let safeName = baseName.isEmpty ? "Imported-PDF" : baseName
            let destination = folder
                .appendingPathComponent("\(safeName)-\(UUID().uuidString.prefix(8))")
                .appendingPathExtension("pdf")

            try data.write(to: destination, options: .atomic)
            return destination
        }.value
    }

    private static func coordinatedRead(from url: URL) throws -> Data {
        var coordinationError: NSError?
        var readResult: Result<Data, Error>?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { coordinatedURL in
            readResult = Result {
                try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
            }
        }

        if let readResult {
            return try readResult.get()
        }
        if let coordinationError {
            throw coordinationError
        }

        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }
}

private enum RobustPDFImportError: LocalizedError {
    case folderSelected
    case emptyFile
    case notPDF
    case unreadablePDF

    var errorDescription: String? {
        switch self {
        case .folderSelected:
            return "Please select a PDF file, not a folder."
        case .emptyFile:
            return "The selected file is empty or has not finished downloading from Files."
        case .notPDF:
            return "The selected item is not a valid PDF file."
        case .unreadablePDF:
            return "This PDF is damaged, password-protected, or cannot be opened by iOS PDFKit."
        }
    }
}
