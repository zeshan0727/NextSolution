import SwiftUI
import UIKit
import PDFKit
import PencilKit
import UniformTypeIdentifiers

struct ProContentView: View {
    @StateObject private var model = PDFEditorModel()

    @State private var showingImporter = false
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
    @State private var shareItem: ProShareItem?
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
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: model.exportDocument(kind: exportKind),
                contentType: .pdf,
                defaultFilename: model.exportFilename(kind: exportKind)
            ) { result in
                switch result {
                case .success:
                    model.presentMessage(exportKind == .secureRasterized
                        ? "A secure flattened PDF copy was exported. Text underneath redactions cannot be selected or recovered from that copy."
                        : "The edited PDF was exported successfully.")
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
                        model.presentMessage("Select the existing date first, then open Change Date again.")
                        showingDateEditor = false
                        return
                    }
                    model.replaceText(draft: draft, with: text, style: style.mergingDetectedStyle(from: draft))
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
                ProShareSheet(activityItems: [item.url])
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
                    ProEditorSidebar(
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
                        onShare: shareEditable,
                        onExport: {
                            exportKind = .editable
                            showingExporter = true
                        }
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
        if totalWidth >= 800 { return 210 }
        if totalWidth >= 600 { return 180 }
        return min(142, max(124, totalWidth * 0.34))
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
                    Text("Open a PDF from Files. All professional editing tools will appear in the left sidebar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("Choose PDF from Files", systemImage: "folder.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isImporting)

                VStack(alignment: .leading, spacing: 12) {
                    ProFeatureRow(icon: "character.cursor.ibeam", title: "Edit existing text", detail: "Select text, then replace names, amounts or dates.")
                    ProFeatureRow(icon: "signature", title: "Sign and draw", detail: "Add signatures and freehand ink.")
                    ProFeatureRow(icon: "highlighter", title: "Markup and redact", detail: "Highlight, whiteout and permanently redact.")
                    ProFeatureRow(icon: "sidebar.left", title: "Professional sidebar", detail: "Every editing command appears after the document opens.")
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(24)
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(importStatus)
                    .font(.headline)
                Text("Cloud PDFs may need a moment to download from Files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 18)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                showingImporter = true
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

            Button(action: shareEditable) {
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

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            model.present(error: error)
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            importPDF(from: selectedURL)
        }
    }

    private func importPDF(from selectedURL: URL) {
        guard !isImporting else { return }
        isImporting = true
        importStatus = "Downloading PDF from Files…"

        Task {
            do {
                let localURL = try await ProPDFImportCoordinator.makeLocalCopy(of: selectedURL)
                importStatus = "Opening PDF…"
                await Task.yield()
                model.open(url: localURL)
                sidebarVisible = true
            } catch {
                model.present(error: error)
            }
            isImporting = false
        }
    }

    private func openExistingTextEditor() {
        guard let draft = model.makeTextEditDraft() else {
            model.presentMessage("Select existing text first. Long-press a word or date in the PDF, adjust the selection handles, then tap Edit Text.")
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

    private func shareEditable() {
        if let url = model.makeShareFile(kind: .editable) {
            shareItem = ProShareItem(url: url)
        }
    }
}

private struct ProEditorSidebar: View {
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
    let onShare: () -> Void
    let onExport: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sidebarHeader

                ProSidebarSection(title: "TEXT") {
                    ProSidebarButton("Edit Text", icon: "character.cursor.ibeam", primary: true, action: onEditText)
                    ProSidebarButton("Add Text", icon: "text.badge.plus", action: onAddText)
                    ProSidebarButton("Change Date", icon: "calendar", action: onDate)
                    ProSidebarButton("Remove Text", icon: "eraser") { model.removeSelectedText() }
                        .opacity(model.hasTextSelection ? 1 : 0.55)
                }

                ProSidebarSection(title: "MARKUP") {
                    ProSidebarButton("Highlight", icon: "highlighter") { model.markSelection(.highlight) }
                    ProSidebarButton("Underline", icon: "underline") { model.markSelection(.underline) }
                    ProSidebarButton("Strike Out", icon: "strikethrough") { model.markSelection(.strikeOut) }
                    ProSidebarButton("Whiteout", icon: "rectangle.fill") { model.redactSelection(coverColor: .white) }
                    ProSidebarButton("Redact", icon: "eye.slash.fill") { model.redactSelection(coverColor: .black) }
                }

                ProSidebarSection(title: "SIGN & DRAW") {
                    ProSidebarButton("Signature", icon: "signature", action: onSignature)
                    ProSidebarButton("Draw", icon: "pencil.tip.crop.circle", action: onDraw)
                }

                ProSidebarSection(title: "SHAPES") {
                    ForEach(PDFShapeKind.allCases) { shape in
                        ProSidebarButton(shape.title, icon: shape.systemImage) {
                            model.addShape(shape)
                        }
                    }
                }

                ProSidebarSection(title: "DOCUMENT") {
                    ProSidebarButton("Pages", icon: "rectangle.stack", action: onPages)
                    ProSidebarButton("Search", icon: "magnifyingglass", action: onSearch)
                    ProSidebarButton("Undo", icon: "arrow.uturn.backward") { model.undo() }
                        .disabled(!model.canUndo)
                    ProSidebarButton("Redo", icon: "arrow.uturn.forward") { model.redo() }
                        .disabled(!model.canRedo)
                    if model.hasSelectedAnnotation {
                        ProSidebarButton("Delete Selected", icon: "trash", destructive: true) {
                            model.deleteSelectedAnnotation()
                        }
                    }
                }

                ProSidebarSection(title: "SAVE & SHARE") {
                    ProSidebarButton("Save", icon: "square.and.arrow.down", action: onSave)
                    ProSidebarButton("Secure Save", icon: "lock.doc", action: onSecureSave)
                    ProSidebarButton("Export to Files", icon: "folder.badge.plus", action: onExport)
                    ProSidebarButton("Share", icon: "square.and.arrow.up", action: onShare)
                }
            }
            .padding(10)
        }
        .background(.ultraThinMaterial)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Edit Tools", systemImage: "slider.horizontal.3")
                .font(.headline)
            Text(model.hasTextSelection ? "Selected text is ready" : "Select text or choose a tool")
                .font(.caption2)
                .foregroundStyle(model.hasTextSelection ? .blue : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }
}

private struct ProSidebarSection<Content: View>: View {
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

private struct ProSidebarButton: View {
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
        if primary { return .blue }
        return Color.secondary.opacity(0.11)
    }
}

private struct ProFeatureRow: View {
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

private struct ProShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ProShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

private enum ProPDFImportCoordinator {
    static func makeLocalCopy(of sourceURL: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { sourceURL.stopAccessingSecurityScopedResource() }
            }

            let fileManager = FileManager.default
            let documents = try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let importFolder = documents.appendingPathComponent("Imported PDFs", isDirectory: true)
            try fileManager.createDirectory(at: importFolder, withIntermediateDirectories: true)

            let originalName = sourceURL.deletingPathExtension().lastPathComponent
            let safeName = originalName.isEmpty ? "Imported-PDF" : originalName
            let destination = importFolder
                .appendingPathComponent("\(safeName)-\(UUID().uuidString.prefix(8))")
                .appendingPathExtension("pdf")

            var coordinationError: NSError?
            var operationError: Error?
            var copied = false

            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: sourceURL, options: [.withoutChanges], error: &coordinationError) { coordinatedURL in
                do {
                    try fileManager.copyItem(at: coordinatedURL, to: destination)
                    copied = true
                } catch {
                    operationError = error
                }
            }

            if !copied {
                do {
                    let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
                    try data.write(to: destination, options: .atomic)
                    copied = true
                } catch {
                    if let operationError { throw operationError }
                    if let coordinationError { throw coordinationError }
                    throw error
                }
            }

            guard copied,
                  fileManager.fileExists(atPath: destination.path),
                  let attributes = try? fileManager.attributesOfItem(atPath: destination.path),
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value > 0 else {
                throw CocoaError(.fileReadUnknown)
            }

            return destination
        }.value
    }
}
