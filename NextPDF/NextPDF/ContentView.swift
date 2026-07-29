import SwiftUI
import UIKit
import PDFKit
import PencilKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = PDFEditorModel()

    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingAddText = false
    @State private var showingDateEditor = false
    @State private var showingSignature = false
    @State private var showingDrawing = false
    @State private var showingPages = false
    @State private var showingSearch = false
    @State private var editDraft: TextEditDraft?
    @State private var shareItem: ShareItem?
    @State private var exportKind: PDFExportKind = .editable

    var body: some View {
        NavigationStack {
            ZStack {
                if let document = model.document {
                    PDFKitEditorView(document: document, model: model)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    emptyState
                }
            }
            .navigationTitle(model.documentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.document != nil {
                    VStack(spacing: 0) {
                        editorStatusBar
                        ProToolDock(
                            hasTextSelection: model.hasTextSelection,
                            hasSelectedAnnotation: model.hasSelectedAnnotation,
                            onEditText: openExistingTextEditor,
                            onAddText: { showingAddText = true },
                            onRemoveText: { model.removeSelectedText() },
                            onDate: openDateEditor,
                            onHighlight: { model.markSelection(.highlight) },
                            onUnderline: { model.markSelection(.underline) },
                            onStrikeout: { model.markSelection(.strikeOut) },
                            onRedactBlack: { model.redactSelection(coverColor: .black) },
                            onWhiteout: { model.redactSelection(coverColor: .white) },
                            onSignature: { showingSignature = true },
                            onDraw: { showingDrawing = true },
                            onShape: { model.addShape($0) },
                            onPages: { showingPages = true },
                            onDeleteAnnotation: { model.deleteSelectedAnnotation() }
                        )
                    }
                    .background(.ultraThinMaterial)
                }
            }
            .sheet(isPresented: $showingImporter) {
                PDFDocumentPicker { url in
                    showingImporter = false
                    guard let url else { return }
                    model.open(url: url)
                }
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
                ShareSheet(activityItems: [item.url])
            }
            .alert("Next PDF Pro", isPresented: $model.showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(model.alertMessage)
            }
        }
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
                    Text("Edit existing text, replace dates, sign, draw, highlight, redact and organise pages.")
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

                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "character.cursor.ibeam", title: "Edit existing text", detail: "Select text inside the PDF, then replace or remove it.")
                    FeatureRow(icon: "signature", title: "Sign and draw", detail: "Create handwritten signatures and ink annotations.")
                    FeatureRow(icon: "highlighter", title: "Markup and redact", detail: "Highlight, underline, strike out, whiteout or securely redact.")
                    FeatureRow(icon: "rectangle.stack", title: "Manage pages", detail: "Rotate, duplicate, reorder, crop, add and delete pages.")
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(24)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingImporter = true
            } label: {
                Label("Open", systemImage: "folder")
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                model.saveInsideApp(kind: .editable)
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(model.document == nil)

            Button {
                if let url = model.makeShareFile(kind: .editable) {
                    shareItem = ShareItem(url: url)
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(model.document == nil)

            Menu {
                Button("Search PDF", systemImage: "magnifyingglass") {
                    showingSearch = true
                }

                Divider()

                Button("Undo", systemImage: "arrow.uturn.backward") {
                    model.undo()
                }
                .disabled(!model.canUndo)

                Button("Redo", systemImage: "arrow.uturn.forward") {
                    model.redo()
                }
                .disabled(!model.canRedo)

                Divider()

                Button("Save Editable Copy", systemImage: "doc.badge.plus") {
                    model.saveInsideApp(kind: .editable)
                }

                Button("Save Secure Flattened Copy", systemImage: "lock.doc") {
                    model.saveInsideApp(kind: .secureRasterized)
                }

                Button("Export Editable to Files", systemImage: "folder.badge.plus") {
                    exportKind = .editable
                    showingExporter = true
                }

                Button("Export Secure Flattened to Files", systemImage: "lock.square") {
                    exportKind = .secureRasterized
                    showingExporter = true
                }

                Button("Share Secure Flattened Copy", systemImage: "lock.open.display") {
                    if let url = model.makeShareFile(kind: .secureRasterized) {
                        shareItem = ShareItem(url: url)
                    }
                }

                Divider()

                Button("Document Information", systemImage: "info.circle") {
                    model.showDocumentInformation()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(model.document == nil)
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
}

private struct FeatureRow: View {
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

private struct ProToolDock: View {
    let hasTextSelection: Bool
    let hasSelectedAnnotation: Bool
    let onEditText: () -> Void
    let onAddText: () -> Void
    let onRemoveText: () -> Void
    let onDate: () -> Void
    let onHighlight: () -> Void
    let onUnderline: () -> Void
    let onStrikeout: () -> Void
    let onRedactBlack: () -> Void
    let onWhiteout: () -> Void
    let onSignature: () -> Void
    let onDraw: () -> Void
    let onShape: (PDFShapeKind) -> Void
    let onPages: () -> Void
    let onDeleteAnnotation: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ToolButton(title: "Edit Text", icon: "character.cursor.ibeam", isPrimary: true, action: onEditText)
                ToolButton(title: "Add Text", icon: "text.badge.plus", action: onAddText)
                ToolButton(title: "Remove", icon: "eraser", action: onRemoveText)
                    .opacity(hasTextSelection ? 1 : 0.55)
                ToolButton(title: "Date", icon: "calendar", action: onDate)

                Menu {
                    Button("Highlight") { onHighlight() }
                    Button("Underline") { onUnderline() }
                    Button("Strike Out") { onStrikeout() }
                } label: {
                    ToolLabel(title: "Markup", icon: "highlighter")
                }

                Menu {
                    Button("Black Redaction") { onRedactBlack() }
                    Button("Whiteout / Remove Text") { onWhiteout() }
                } label: {
                    ToolLabel(title: "Redact", icon: "rectangle.fill")
                }

                ToolButton(title: "Sign", icon: "signature", action: onSignature)
                ToolButton(title: "Draw", icon: "pencil.tip.crop.circle", action: onDraw)

                Menu {
                    ForEach(PDFShapeKind.allCases) { shape in
                        Button(shape.title, systemImage: shape.systemImage) {
                            onShape(shape)
                        }
                    }
                } label: {
                    ToolLabel(title: "Shapes", icon: "square.on.circle")
                }

                ToolButton(title: "Pages", icon: "rectangle.stack", action: onPages)

                if hasSelectedAnnotation {
                    ToolButton(title: "Delete", icon: "trash", role: .destructive, action: onDeleteAnnotation)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }
}

private struct ToolButton: View {
    let title: String
    let icon: String
    var isPrimary = false
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            ToolLabel(title: title, icon: icon, isPrimary: isPrimary)
        }
        .buttonStyle(.plain)
    }
}

private struct ToolLabel: View {
    let title: String
    let icon: String
    var isPrimary = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isPrimary ? Color.white : Color.primary)
        .frame(minWidth: 62)
        .padding(.horizontal, 5)
        .padding(.vertical, 8)
        .background(isPrimary ? Color.blue : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PDFDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void

        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
