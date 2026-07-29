import SwiftUI
import UIKit
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = PDFEditorModel()
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingTextEditor = false
    @State private var textDraft = ""
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            ZStack {
                if let document = model.document {
                    PDFKitView(document: document, model: model)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 54))
                            .foregroundStyle(.secondary)
                        Text("Open a PDF")
                            .font(.title2.bold())
                        Text("Choose a PDF from the Files app to begin editing.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Choose from Files", systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Next PDF")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Open", systemImage: "folder")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        model.saveInsideApp()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.document == nil)

                    Button {
                        if let url = model.makeShareFile() {
                            shareItem = ShareItem(url: url)
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.document == nil)

                    Menu {
                        Button("Add Text", systemImage: "text.badge.plus") {
                            textDraft = ""
                            showingTextEditor = true
                        }
                        .disabled(model.document == nil)

                        Button("Delete Last Annotation", systemImage: "trash", role: .destructive) {
                            model.deleteSelectedAnnotation()
                        }
                        .disabled(model.document == nil)

                        Button("Crop Current Page", systemImage: "crop") {
                            model.cropCurrentPage()
                        }
                        .disabled(model.document == nil)

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

                        Button("Export to Files", systemImage: "folder.badge.plus") {
                            showingExporter = true
                        }
                        .disabled(model.document == nil)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
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
                document: model.exportDocument,
                contentType: .pdf,
                defaultFilename: model.exportFilename
            ) { result in
                switch result {
                case .success:
                    model.presentMessage("The edited PDF was exported successfully.")
                case .failure(let error):
                    model.present(error: error)
                }
            }
            .sheet(isPresented: $showingTextEditor) {
                TextInsertSheet(text: $textDraft, fonts: model.availableFonts) { text, fontName, size in
                    model.addText(text, fontName: fontName, size: size)
                    showingTextEditor = false
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(activityItems: [item.url])
            }
            .alert("Next PDF", isPresented: $model.showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(model.alertMessage)
            }
        }
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PDFDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

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

private struct TextInsertSheet: View {
    @Environment(\.dismiss) private var dismiss
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
                    Button("Cancel") {
                        text = ""
                        dismiss()
                    }
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
        model.attach(pdfView: uiView)
    }
}

@MainActor
final class PDFEditorModel: ObservableObject {
    private struct EditAction {
        let undo: () -> Void
        let redo: () -> Void
    }

    @Published var document: PDFDocument?
    @Published var showingAlert = false
    @Published var alertMessage = ""
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    weak var pdfView: PDFView?
    private var selectedAnnotation: PDFAnnotation?
    private var undoStack: [EditAction] = []
    private var redoStack: [EditAction] = []
    private var sourceURL: URL?

    var availableFonts: [String] {
        UIFont.familyNames
            .flatMap { UIFont.fontNames(forFamilyName: $0) }
            .sorted()
    }

    var exportFilename: String {
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "Edited-PDF"
        return "\(base)-edited.pdf"
    }

    var exportDocument: PDFFileDocument? {
        guard let data = document?.dataRepresentation() else { return nil }
        return PDFFileDocument(data: data)
    }

    func attach(pdfView: PDFView) {
        self.pdfView = pdfView
    }

    func open(url: URL) {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            guard let pdf = PDFDocument(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            sourceURL = url
            document = pdf
            selectedAnnotation = nil
            undoStack.removeAll()
            redoStack.removeAll()
            refreshUndoState()
        } catch {
            present(error: error)
        }
    }

    func saveInsideApp() {
        do {
            guard let data = document?.dataRepresentation() else {
                throw CocoaError(.fileWriteUnknown)
            }

            let documentsDirectory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let savedFolder = documentsDirectory.appendingPathComponent("Saved PDFs", isDirectory: true)
            try FileManager.default.createDirectory(at: savedFolder, withIntermediateDirectories: true)

            let destination = uniqueDestination(in: savedFolder, filename: exportFilename)
            try data.write(to: destination, options: .atomic)
            presentMessage("Saved inside Next PDF. You can also find it in Files > On My iPhone > Next PDF > Saved PDFs.\n\n\(destination.lastPathComponent)")
        } catch {
            present(error: error)
        }
    }

    func makeShareFile() -> URL? {
        do {
            guard let data = document?.dataRepresentation() else {
                throw CocoaError(.fileWriteUnknown)
            }

            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NextPDF-Share", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(exportFilename)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            present(error: error)
            return nil
        }
    }

    func addText(_ text: String, fontName: String, size: CGFloat) {
        guard let page = pdfView?.currentPage ?? document?.page(at: 0) else { return }
        let pageBounds = page.bounds(for: .mediaBox)
        let width = min(pageBounds.width * 0.72, 420)
        let height = max(size * 2.2, 44)
        let rect = CGRect(
            x: pageBounds.midX - width / 2,
            y: pageBounds.midY - height / 2,
            width: width,
            height: height
        )

        let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = UIFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
        annotation.fontColor = .label
        annotation.color = .clear
        page.addAnnotation(annotation)
        selectedAnnotation = annotation

        registerUndo(
            undo: { page.removeAnnotation(annotation) },
            redo: { page.addAnnotation(annotation) }
        )
    }

    func deleteSelectedAnnotation() {
        guard let page = pdfView?.currentPage,
              let annotation = selectedAnnotation ?? page.annotations.last else { return }

        page.removeAnnotation(annotation)
        selectedAnnotation = nil
        registerUndo(
            undo: { page.addAnnotation(annotation) },
            redo: { page.removeAnnotation(annotation) }
        )
    }

    func cropCurrentPage() {
        guard let page = pdfView?.currentPage else { return }
        let original = page.bounds(for: .cropBox)
        let cropped = original.insetBy(dx: original.width * 0.05, dy: original.height * 0.05)
        guard cropped.width > 0, cropped.height > 0 else { return }

        page.setBounds(cropped, for: .cropBox)
        registerUndo(
            undo: { page.setBounds(original, for: .cropBox) },
            redo: { page.setBounds(cropped, for: .cropBox) }
        )
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        action.undo()
        redoStack.append(action)
        refreshUndoState()
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        action.redo()
        undoStack.append(action)
        refreshUndoState()
    }

    func present(error: Error) {
        alertMessage = error.localizedDescription
        showingAlert = true
    }

    func presentMessage(_ message: String) {
        alertMessage = message
        showingAlert = true
    }

    private func uniqueDestination(in folder: URL, filename: String) -> URL {
        let baseURL = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return baseURL }

        let name = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let datedName = "\(name)-\(formatter.string(from: Date())).\(ext)"
        return folder.appendingPathComponent(datedName)
    }

    private func registerUndo(undo: @escaping () -> Void, redo: @escaping () -> Void) {
        undoStack.append(EditAction(undo: undo, redo: redo))
        redoStack.removeAll()
        refreshUndoState()
    }

    private func refreshUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
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
