import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = PDFEditorModel()
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingTextEditor = false
    @State private var textDraft = ""

    var body: some View {
        NavigationStack {
            ZStack {
                if let document = model.document {
                    PDFKitView(document: document, model: model)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "Open a PDF",
                        systemImage: "doc.richtext",
                        description: Text("Choose a PDF to start editing, adding text, deleting annotations, or cropping pages.")
                    )
                }
            }
            .navigationTitle("Next PDF")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Open", systemImage: "folder")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("Add Text", systemImage: "text.badge.plus") {
                            textDraft = ""
                            showingTextEditor = true
                        }
                        Button("Delete Selected", systemImage: "trash", role: .destructive) {
                            model.deleteSelectedAnnotation()
                        }
                        Button("Crop Current Page", systemImage: "crop") {
                            model.cropCurrentPage()
                        }
                        Button("Undo", systemImage: "arrow.uturn.backward") {
                            model.undo()
                        }
                        .disabled(!model.canUndo)
                        Button("Redo", systemImage: "arrow.uturn.forward") {
                            model.redo()
                        }
                        .disabled(!model.canRedo)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }

                    Button {
                        showingExporter = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.document == nil)
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                model.open(result: result)
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: model.exportDocument,
                contentType: .pdf,
                defaultFilename: model.exportFilename
            ) { _ in }
            .sheet(isPresented: $showingTextEditor) {
                TextInsertSheet(text: $textDraft, fonts: model.availableFonts) { text, fontName, size in
                    model.addText(text, fontName: fontName, size: size)
                    showingTextEditor = false
                }
            }
            .alert("Next PDF", isPresented: $model.showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(model.errorMessage)
            }
        }
    }
}

private struct TextInsertSheet: View {
    @Binding var text: String
    let fonts: [String]
    let onInsert: (String, String, CGFloat) -> Void

    @State private var selectedFont = UIFont.systemFont(ofSize: 17).fontName
    @State private var size: Double = 18

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                }
                Section("Formatting") {
                    Picker("Font", selection: $selectedFont) {
                        ForEach(fonts, id: \.self) { font in
                            Text(font).tag(font)
                        }
                    }
                    Slider(value: $size, in: 8...72, step: 1)
                    Text("Size: \(Int(size)) pt")
                }
            }
            .navigationTitle("Add Text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { text = "" }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") {
                        onInsert(text, selectedFont, CGFloat(size))
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @ObservedObject var model: PDFEditorModel

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        view.backgroundColor = .secondarySystemBackground
        view.usePageViewController(false)
        model.attach(pdfView: view)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
        }
    }
}

@MainActor
final class PDFEditorModel: ObservableObject {
    @Published var document: PDFDocument?
    @Published var showingError = false
    @Published var errorMessage = ""
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    weak var pdfView: PDFView?
    private var selectedAnnotation: PDFAnnotation?
    private var undoStack: [() -> Void] = []
    private var redoStack: [() -> Void] = []
    private var sourceURL: URL?

    var availableFonts: [String] {
        UIFont.familyNames
            .flatMap { UIFont.fontNames(forFamilyName: $0) }
            .sorted()
    }

    var exportFilename: String {
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "Edited PDF"
        return "\(base)-edited.pdf"
    }

    var exportDocument: PDFFileDocument? {
        guard let data = document?.dataRepresentation() else { return nil }
        return PDFFileDocument(data: data)
    }

    func attach(pdfView: PDFView) {
        self.pdfView = pdfView
    }

    func open(result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                throw CocoaError(.fileReadNoPermission)
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url), let pdf = PDFDocument(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            sourceURL = url
            document = pdf
            undoStack.removeAll()
            redoStack.removeAll()
            refreshUndoState()
        } catch {
            show(error)
        }
    }

    func addText(_ text: String, fontName: String, size: CGFloat) {
        guard let page = pdfView?.currentPage ?? document?.page(at: 0) else { return }
        let pageBounds = page.bounds(for: .mediaBox)
        let width = min(pageBounds.width * 0.72, 420)
        let height = max(size * 2.2, 44)
        let rect = CGRect(x: pageBounds.midX - width / 2, y: pageBounds.midY - height / 2, width: width, height: height)
        let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = UIFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
        annotation.fontColor = .label
        annotation.color = .clear
        page.addAnnotation(annotation)
        selectedAnnotation = annotation

        registerUndo {
            page.removeAnnotation(annotation)
        } redo: {
            page.addAnnotation(annotation)
        }
    }

    func deleteSelectedAnnotation() {
        guard let page = pdfView?.currentPage,
              let annotation = selectedAnnotation ?? page.annotations.last else { return }
        page.removeAnnotation(annotation)
        selectedAnnotation = nil
        registerUndo {
            page.addAnnotation(annotation)
        } redo: {
            page.removeAnnotation(annotation)
        }
    }

    func cropCurrentPage() {
        guard let page = pdfView?.currentPage else { return }
        let original = page.bounds(for: .cropBox)
        let insetX = original.width * 0.05
        let insetY = original.height * 0.05
        let cropped = original.insetBy(dx: insetX, dy: insetY)
        page.setBounds(cropped, for: .cropBox)
        registerUndo {
            page.setBounds(original, for: .cropBox)
        } redo: {
            page.setBounds(cropped, for: .cropBox)
        }
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        action()
        redoStack.append(action)
        refreshUndoState()
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        action()
        undoStack.append(action)
        refreshUndoState()
    }

    private func registerUndo(undo: @escaping () -> Void, redo: @escaping () -> Void) {
        undoStack.append(undo)
        redoStack.removeAll()
        refreshUndoState()
    }

    private func refreshUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}

struct PDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
