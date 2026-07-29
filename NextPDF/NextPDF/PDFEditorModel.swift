import SwiftUI
import UIKit
import PDFKit
import PencilKit
import UniformTypeIdentifiers

// MARK: - Shared editor types

enum PDFExportKind: String {
    case editable
    case secureRasterized
}

enum PDFMarkupKind {
    case highlight
    case underline
    case strikeOut

    var subtype: PDFAnnotationSubtype {
        switch self {
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikeOut: return .strikeOut
        }
    }

    var color: UIColor {
        switch self {
        case .highlight: return UIColor.systemYellow.withAlphaComponent(0.55)
        case .underline: return UIColor.systemBlue
        case .strikeOut: return UIColor.systemRed
        }
    }
}

enum PDFShapeKind: String, CaseIterable, Identifiable {
    case rectangle
    case circle
    case checkmark
    case cross

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .checkmark: return "Check Mark"
        case .cross: return "Cross"
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .checkmark: return "checkmark"
        case .cross: return "xmark"
        }
    }
}

enum InkMode {
    case signature
    case drawing
}

struct PDFTextStyle {
    var fontName: String
    var fontSize: CGFloat
    var textColor: UIColor
    var coverColor: UIColor
    var alignment: NSTextAlignment

    static var standard: PDFTextStyle {
        PDFTextStyle(
            fontName: UIFont.systemFont(ofSize: 17).fontName,
            fontSize: 18,
            textColor: .label,
            coverColor: .white,
            alignment: .left
        )
    }

    func mergingDetectedStyle(from draft: TextEditDraft) -> PDFTextStyle {
        var merged = self
        merged.fontName = draft.detectedFontName
        merged.fontSize = draft.detectedFontSize
        merged.textColor = draft.detectedTextColor
        return merged
    }
}

struct TextEditDraft: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let bounds: CGRect
    let originalText: String
    let detectedFontName: String
    let detectedFontSize: CGFloat
    let detectedTextColor: UIColor
    let detectedAlignment: NSTextAlignment

    var detectedStyle: PDFTextStyle {
        PDFTextStyle(
            fontName: detectedFontName,
            fontSize: detectedFontSize,
            textColor: detectedTextColor,
            coverColor: .white,
            alignment: detectedAlignment
        )
    }
}

struct PDFSearchHit: Identifiable {
    let id = UUID()
    let selection: PDFSelection
    let pageNumber: Int
    let preview: String
}

// MARK: - Editing model

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
    @Published private(set) var hasTextSelection = false
    @Published private(set) var hasSelectedAnnotation = false
    @Published private(set) var selectedAnnotationName = "Annotation"
    @Published private(set) var currentPageNumber = 1
    @Published private(set) var pageCount = 0
    @Published private(set) var documentTitle = "Next PDF Pro"

    weak var pdfView: PDFView?

    private var sourceURL: URL?
    private var selectedAnnotation: PDFAnnotation?
    private weak var selectedAnnotationPage: PDFPage?
    private var undoStack: [EditAction] = []
    private var redoStack: [EditAction] = []
    private var lastTapPoint: CGPoint?
    private weak var lastTapPage: PDFPage?

    private var moveStartPoint: CGPoint?
    private var moveStartBounds: CGRect?
    private weak var movePage: PDFPage?

    var availableFonts: [String] {
        UIFont.familyNames
            .flatMap { UIFont.fontNames(forFamilyName: $0) }
            .sorted()
    }

    // MARK: Document lifecycle

    func attach(pdfView: PDFView) {
        self.pdfView = pdfView
        refreshSelectionState()
        refreshPageState()
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
            documentTitle = url.deletingPathExtension().lastPathComponent
            document = pdf
            pdfView?.document = pdf
            selectedAnnotation = nil
            selectedAnnotationPage = nil
            undoStack.removeAll()
            redoStack.removeAll()
            refreshUndoState()
            refreshDocumentState()
        } catch {
            present(error: error)
        }
    }

    func selectionDidChange() {
        refreshSelectionState()
    }

    func pageDidChange() {
        refreshPageState()
    }

    // MARK: Existing text editing

    func makeTextEditDraft() -> TextEditDraft? {
        guard let selection = pdfView?.currentSelection,
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let page = selection.pages.first,
              let document,
              document.index(for: page) != NSNotFound else {
            return nil
        }

        let bounds = selection.bounds(for: page).standardized
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }

        var detectedFont = UIFont.systemFont(ofSize: max(10, bounds.height * 0.72))
        var detectedColor = UIColor.label
        var alignment: NSTextAlignment = .left

        if let attributed = selection.attributedString, attributed.length > 0 {
            if let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
                detectedFont = font
            }
            if let color = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor {
                detectedColor = color
            }
            if let paragraph = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                alignment = paragraph.alignment
            }
        }

        return TextEditDraft(
            pageIndex: document.index(for: page),
            bounds: bounds,
            originalText: text,
            detectedFontName: detectedFont.fontName,
            detectedFontSize: max(8, detectedFont.pointSize),
            detectedTextColor: detectedColor,
            detectedAlignment: alignment
        )
    }

    func replaceText(draft: TextEditDraft, with newText: String, style: PDFTextStyle) {
        guard let page = document?.page(at: draft.pageIndex) else { return }

        let cover = makeCoverAnnotation(bounds: draft.bounds.insetBy(dx: -1.5, dy: -1.5), color: style.coverColor)
        page.addAnnotation(cover)

        var annotations: [PDFAnnotation] = [cover]
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            let estimatedWidth = max(
                draft.bounds.width,
                min(page.bounds(for: .cropBox).width - draft.bounds.minX - 8,
                    CGFloat(trimmed.count) * style.fontSize * 0.58)
            )
            let textBounds = CGRect(
                x: draft.bounds.minX,
                y: draft.bounds.minY - max(1, style.fontSize * 0.08),
                width: max(estimatedWidth, 12),
                height: max(draft.bounds.height * 1.35, style.fontSize * 1.45)
            )

            let replacement = makeFreeTextAnnotation(text: trimmed, bounds: textBounds, style: style)
            page.addAnnotation(replacement)
            annotations.append(replacement)
            select(annotation: replacement, on: page)
        } else {
            select(annotation: cover, on: page)
        }

        registerAnnotationBatch(annotations, on: page)
        clearTextSelection()
        refreshDisplay()
    }

    func removeSelectedText() {
        guard let selection = pdfView?.currentSelection,
              let document else {
            presentMessage("Select the text you want to remove first.")
            return
        }

        let lines = selection.selectionsByLine()
        let selections = lines.isEmpty ? [selection] : lines
        var records: [(PDFPage, PDFAnnotation)] = []

        for line in selections {
            for page in line.pages {
                let bounds = line.bounds(for: page).insetBy(dx: -1.2, dy: -1.2)
                guard bounds.width > 0, bounds.height > 0, document.index(for: page) != NSNotFound else { continue }
                let cover = makeCoverAnnotation(bounds: bounds, color: .white)
                page.addAnnotation(cover)
                records.append((page, cover))
            }
        }

        guard !records.isEmpty else { return }
        registerMultiPageAnnotations(records)
        if let last = records.last { select(annotation: last.1, on: last.0) }
        clearTextSelection()
        refreshDisplay()
    }

    func addText(_ text: String, style: PDFTextStyle) {
        guard let page = lastTapPage ?? pdfView?.currentPage ?? document?.page(at: 0) else { return }
        let pageBounds = page.bounds(for: .cropBox)
        let width = min(max(CGFloat(text.count) * style.fontSize * 0.62, 130), pageBounds.width * 0.82)
        let height = max(style.fontSize * 2.0, 44)
        let centre = lastTapPage === page ? (lastTapPoint ?? CGPoint(x: pageBounds.midX, y: pageBounds.midY)) : CGPoint(x: pageBounds.midX, y: pageBounds.midY)
        let bounds = CGRect(
            x: min(max(pageBounds.minX + 4, centre.x - width / 2), pageBounds.maxX - width - 4),
            y: min(max(pageBounds.minY + 4, centre.y - height / 2), pageBounds.maxY - height - 4),
            width: width,
            height: height
        )

        let annotation = makeFreeTextAnnotation(text: text, bounds: bounds, style: style)
        page.addAnnotation(annotation)
        select(annotation: annotation, on: page)
        registerAnnotationBatch([annotation], on: page)
        refreshDisplay()
    }

    // MARK: Markup and redaction

    func markSelection(_ kind: PDFMarkupKind) {
        guard let selection = pdfView?.currentSelection else {
            presentMessage("Select text first, then choose a markup tool.")
            return
        }

        let lines = selection.selectionsByLine()
        let selections = lines.isEmpty ? [selection] : lines
        var records: [(PDFPage, PDFAnnotation)] = []

        for line in selections {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: kind.subtype, withProperties: nil)
                annotation.color = kind.color
                annotation.shouldDisplay = true
                annotation.shouldPrint = true
                page.addAnnotation(annotation)
                records.append((page, annotation))
            }
        }

        guard !records.isEmpty else { return }
        registerMultiPageAnnotations(records)
        if let last = records.last { select(annotation: last.1, on: last.0) }
        clearTextSelection()
        refreshDisplay()
    }

    func redactSelection(coverColor: UIColor) {
        guard let selection = pdfView?.currentSelection else {
            presentMessage("Select the text or area first, then choose Redact or Whiteout.")
            return
        }

        let lines = selection.selectionsByLine()
        let selections = lines.isEmpty ? [selection] : lines
        var records: [(PDFPage, PDFAnnotation)] = []

        for line in selections {
            for page in line.pages {
                let bounds = line.bounds(for: page).insetBy(dx: -1.5, dy: -1.5)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                let cover = makeCoverAnnotation(bounds: bounds, color: coverColor)
                page.addAnnotation(cover)
                records.append((page, cover))
            }
        }

        guard !records.isEmpty else { return }
        registerMultiPageAnnotations(records)
        if let last = records.last { select(annotation: last.1, on: last.0) }
        clearTextSelection()
        refreshDisplay()

        if coverColor == .black {
            presentMessage("Redaction marks were added. Use Save or Export Secure Flattened Copy to permanently burn them into a non-selectable PDF.")
        }
    }

    // MARK: Signature, drawing and shapes

    func addInkDrawing(_ drawing: PKDrawing, color: UIColor, lineWidth: CGFloat, mode: InkMode) {
        guard !drawing.strokes.isEmpty,
              let page = lastTapPage ?? pdfView?.currentPage ?? document?.page(at: 0) else { return }

        let sourceBounds = drawing.bounds.insetBy(dx: -4, dy: -4)
        guard sourceBounds.width > 0, sourceBounds.height > 0 else { return }

        let pageBounds = page.bounds(for: .cropBox)
        let targetWidth = mode == .signature ? min(pageBounds.width * 0.58, 330) : min(pageBounds.width * 0.78, 440)
        let ratio = max(0.18, sourceBounds.height / sourceBounds.width)
        let targetHeight = min(max(targetWidth * ratio, mode == .signature ? 70 : 100), pageBounds.height * 0.42)
        let centre = lastTapPage === page ? (lastTapPoint ?? CGPoint(x: pageBounds.midX, y: pageBounds.midY)) : CGPoint(x: pageBounds.midX, y: pageBounds.midY)
        let target = CGRect(
            x: min(max(pageBounds.minX + 6, centre.x - targetWidth / 2), pageBounds.maxX - targetWidth - 6),
            y: min(max(pageBounds.minY + 6, centre.y - targetHeight / 2), pageBounds.maxY - targetHeight - 6),
            width: targetWidth,
            height: targetHeight
        )

        let annotation = PDFAnnotation(bounds: target, forType: .ink, withProperties: nil)
        annotation.color = color
        let border = PDFBorder()
        border.lineWidth = max(1, lineWidth)
        annotation.border = border
        annotation.shouldDisplay = true
        annotation.shouldPrint = true

        for stroke in drawing.strokes {
            let path = UIBezierPath()
            var isFirst = true
            for point in stroke.path {
                let nx = (point.location.x - sourceBounds.minX) / sourceBounds.width
                let ny = (point.location.y - sourceBounds.minY) / sourceBounds.height
                let mapped = CGPoint(
                    x: max(0, min(target.width, nx * target.width)),
                    y: max(0, min(target.height, (1 - ny) * target.height))
                )
                if isFirst {
                    path.move(to: mapped)
                    isFirst = false
                } else {
                    path.addLine(to: mapped)
                }
            }
            if !isFirst { annotation.add(path) }
        }

        page.addAnnotation(annotation)
        select(annotation: annotation, on: page)
        registerAnnotationBatch([annotation], on: page)
        refreshDisplay()
    }

    func addShape(_ kind: PDFShapeKind) {
        guard let page = lastTapPage ?? pdfView?.currentPage ?? document?.page(at: 0) else { return }
        let pageBounds = page.bounds(for: .cropBox)
        let centre = lastTapPage === page ? (lastTapPoint ?? CGPoint(x: pageBounds.midX, y: pageBounds.midY)) : CGPoint(x: pageBounds.midX, y: pageBounds.midY)
        let size = CGSize(width: 120, height: 72)
        let bounds = CGRect(
            x: min(max(pageBounds.minX + 4, centre.x - size.width / 2), pageBounds.maxX - size.width - 4),
            y: min(max(pageBounds.minY + 4, centre.y - size.height / 2), pageBounds.maxY - size.height - 4),
            width: size.width,
            height: size.height
        )

        let annotation: PDFAnnotation
        switch kind {
        case .rectangle, .circle:
            annotation = PDFAnnotation(bounds: bounds, forType: kind == .rectangle ? .square : .circle, withProperties: nil)
            annotation.color = .systemBlue
            annotation.interiorColor = .clear
            let border = PDFBorder()
            border.lineWidth = 2.5
            annotation.border = border
        case .checkmark, .cross:
            annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            annotation.color = kind == .checkmark ? .systemGreen : .systemRed
            let border = PDFBorder()
            border.lineWidth = 4
            annotation.border = border
            let path = UIBezierPath()
            if kind == .checkmark {
                path.move(to: CGPoint(x: 16, y: 34))
                path.addLine(to: CGPoint(x: 48, y: 12))
                path.addLine(to: CGPoint(x: 104, y: 62))
            } else {
                path.move(to: CGPoint(x: 18, y: 14))
                path.addLine(to: CGPoint(x: 102, y: 60))
                path.move(to: CGPoint(x: 102, y: 14))
                path.addLine(to: CGPoint(x: 18, y: 60))
            }
            annotation.add(path)
        }

        annotation.shouldDisplay = true
        annotation.shouldPrint = true
        page.addAnnotation(annotation)
        select(annotation: annotation, on: page)
        registerAnnotationBatch([annotation], on: page)
        refreshDisplay()
    }

    // MARK: Annotation selection and movement

    func handleTap(at viewPoint: CGPoint, in view: PDFView) {
        guard let page = view.page(for: viewPoint, nearest: true) else { return }
        let pagePoint = view.convert(viewPoint, to: page)
        lastTapPoint = pagePoint
        lastTapPage = page

        let found = page.annotations.reversed().first { annotation in
            annotation.bounds.insetBy(dx: -8, dy: -8).contains(pagePoint)
        }

        if let found {
            select(annotation: found, on: page)
        } else {
            clearAnnotationSelection()
        }
    }

    func beginMovingSelectedAnnotation(at viewPoint: CGPoint, in view: PDFView) {
        guard let annotation = selectedAnnotation,
              let page = selectedAnnotationPage,
              let touchedPage = view.page(for: viewPoint, nearest: false),
              touchedPage === page else { return }

        let pagePoint = view.convert(viewPoint, to: page)
        guard annotation.bounds.insetBy(dx: -12, dy: -12).contains(pagePoint) else { return }
        moveStartPoint = pagePoint
        moveStartBounds = annotation.bounds
        movePage = page
    }

    func moveSelectedAnnotation(to viewPoint: CGPoint, in view: PDFView) {
        guard let annotation = selectedAnnotation,
              let page = movePage,
              let start = moveStartPoint,
              let initialBounds = moveStartBounds else { return }

        let pagePoint = view.convert(viewPoint, to: page)
        let dx = pagePoint.x - start.x
        let dy = pagePoint.y - start.y
        let pageBounds = page.bounds(for: .cropBox)
        var moved = initialBounds.offsetBy(dx: dx, dy: dy)
        moved.origin.x = min(max(pageBounds.minX, moved.minX), pageBounds.maxX - moved.width)
        moved.origin.y = min(max(pageBounds.minY, moved.minY), pageBounds.maxY - moved.height)
        annotation.bounds = moved
        refreshDisplay()
    }

    func endMovingSelectedAnnotation() {
        guard let annotation = selectedAnnotation,
              let original = moveStartBounds,
              let page = movePage else {
            resetMoveState()
            return
        }

        let finalBounds = annotation.bounds
        resetMoveState()
        guard original != finalBounds else { return }

        registerUndo(
            undo: { [weak self, weak annotation] in
                annotation?.bounds = original
                self?.refreshDisplay()
            },
            redo: { [weak self, weak annotation] in
                annotation?.bounds = finalBounds
                self?.refreshDisplay()
            }
        )
        selectedAnnotationPage = page
    }

    func deleteSelectedAnnotation() {
        guard let annotation = selectedAnnotation,
              let page = selectedAnnotationPage else {
            presentMessage("Tap an added text box, signature, drawing, shape or markup first, then tap Delete.")
            return
        }

        page.removeAnnotation(annotation)
        clearAnnotationSelection()
        registerUndo(
            undo: { [weak self, weak page, weak annotation] in
                guard let page, let annotation else { return }
                page.addAnnotation(annotation)
                self?.select(annotation: annotation, on: page)
                self?.refreshDisplay()
            },
            redo: { [weak self, weak page, weak annotation] in
                guard let page, let annotation else { return }
                page.removeAnnotation(annotation)
                self?.clearAnnotationSelection()
                self?.refreshDisplay()
            }
        )
        refreshDisplay()
    }

    // MARK: Page management

    func pageThumbnail(at index: Int, size: CGSize = CGSize(width: 110, height: 150)) -> UIImage? {
        document?.page(at: index)?.thumbnail(of: size, for: .cropBox)
    }

    func goToPage(_ index: Int) {
        guard let page = document?.page(at: index) else { return }
        pdfView?.go(to: page)
        refreshPageState()
    }

    func rotateCurrentPage(clockwise: Bool) {
        guard let page = pdfView?.currentPage,
              let document,
              document.index(for: page) != NSNotFound else { return }
        let original = page.rotation
        let updated = normalizedRotation(original + (clockwise ? 90 : -90))
        page.rotation = updated
        registerUndo(
            undo: { [weak self, weak page] in page?.rotation = original; self?.refreshDocumentState() },
            redo: { [weak self, weak page] in page?.rotation = updated; self?.refreshDocumentState() }
        )
        refreshDocumentState()
    }

    func cropCurrentPage(insetPercent: CGFloat = 0.05) {
        guard let page = pdfView?.currentPage else { return }
        let original = page.bounds(for: .cropBox)
        let media = page.bounds(for: .mediaBox)
        let cropped = original.insetBy(dx: original.width * insetPercent, dy: original.height * insetPercent)
            .intersection(media)
        guard cropped.width > 40, cropped.height > 40 else { return }
        page.setBounds(cropped, for: .cropBox)
        registerUndo(
            undo: { [weak self, weak page] in page?.setBounds(original, for: .cropBox); self?.refreshDocumentState() },
            redo: { [weak self, weak page] in page?.setBounds(cropped, for: .cropBox); self?.refreshDocumentState() }
        )
        refreshDocumentState()
    }

    func resetCurrentPageCrop() {
        guard let page = pdfView?.currentPage else { return }
        let original = page.bounds(for: .cropBox)
        let media = page.bounds(for: .mediaBox)
        page.setBounds(media, for: .cropBox)
        registerUndo(
            undo: { [weak self, weak page] in page?.setBounds(original, for: .cropBox); self?.refreshDocumentState() },
            redo: { [weak self, weak page] in page?.setBounds(media, for: .cropBox); self?.refreshDocumentState() }
        )
        refreshDocumentState()
    }

    func addBlankPage(afterCurrent: Bool = true) {
        guard let document else { return }
        let currentIndex = currentPageIndex
        let referenceBounds = pdfView?.currentPage?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: referenceBounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.fill(referenceBounds)
        }
        guard let page = PDFDocument(data: data)?.page(at: 0) else { return }
        let insertion = min(document.pageCount, currentIndex + (afterCurrent ? 1 : 0))
        document.insert(page, at: insertion)
        registerUndo(
            undo: { [weak self, weak document] in document?.removePage(at: insertion); self?.refreshDocumentState() },
            redo: { [weak self, weak document, weak page] in
                guard let page else { return }
                document?.insert(page, at: insertion)
                self?.refreshDocumentState()
            }
        )
        refreshDocumentState()
        goToPage(insertion)
    }

    func duplicateCurrentPage() {
        guard let document,
              let source = pdfView?.currentPage,
              document.index(for: source) != NSNotFound else { return }
        let index = document.index(for: source)
        let bounds = source.bounds(for: .mediaBox)
        let image = renderPageImage(source, scale: 2.0)
        guard let copy = PDFPage(image: image) else { return }
        copy.setBounds(bounds, for: .mediaBox)
        copy.setBounds(source.bounds(for: .cropBox), for: .cropBox)
        let insertion = index + 1
        document.insert(copy, at: insertion)
        registerUndo(
            undo: { [weak self, weak document] in document?.removePage(at: insertion); self?.refreshDocumentState() },
            redo: { [weak self, weak document, weak copy] in
                guard let copy else { return }
                document?.insert(copy, at: insertion)
                self?.refreshDocumentState()
            }
        )
        refreshDocumentState()
        goToPage(insertion)
    }

    func deleteCurrentPage() {
        guard let document, document.pageCount > 1 else {
            presentMessage("A PDF must keep at least one page.")
            return
        }
        let index = currentPageIndex
        guard let page = document.page(at: index) else { return }
        document.removePage(at: index)
        registerUndo(
            undo: { [weak self, weak document, weak page] in
                guard let page else { return }
                document?.insert(page, at: index)
                self?.refreshDocumentState()
            },
            redo: { [weak self, weak document] in
                document?.removePage(at: min(index, max(0, (document?.pageCount ?? 1) - 1)))
                self?.refreshDocumentState()
            }
        )
        refreshDocumentState()
        goToPage(min(index, document.pageCount - 1))
    }

    func moveCurrentPage(by offset: Int) {
        guard let document else { return }
        let from = currentPageIndex
        let to = max(0, min(document.pageCount - 1, from + offset))
        guard from != to, let page = document.page(at: from) else { return }
        document.removePage(at: from)
        document.insert(page, at: to)
        registerUndo(
            undo: { [weak self, weak document, weak page] in
                guard let document, let page else { return }
                document.removePage(at: to)
                document.insert(page, at: from)
                self?.refreshDocumentState()
            },
            redo: { [weak self, weak document, weak page] in
                guard let document, let page else { return }
                document.removePage(at: from)
                document.insert(page, at: to)
                self?.refreshDocumentState()
            }
        )
        refreshDocumentState()
        goToPage(to)
    }

    // MARK: Search

    func search(_ query: String) -> [PDFSearchHit] {
        guard let document else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return document.findString(trimmed, withOptions: [.caseInsensitive]).map { selection in
            let page = selection.pages.first
            let pageNumber = page.map { document.index(for: $0) + 1 } ?? 1
            let text = selection.string ?? trimmed
            return PDFSearchHit(selection: selection, pageNumber: pageNumber, preview: text)
        }
    }

    func goToSearchHit(_ hit: PDFSearchHit) {
        pdfView?.setCurrentSelection(hit.selection, animate: true)
        pdfView?.go(to: hit.selection)
        refreshSelectionState()
        refreshPageState()
    }

    // MARK: Save, share and export

    func exportFilename(kind: PDFExportKind) -> String {
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? documentTitle
        switch kind {
        case .editable: return "\(base)-edited.pdf"
        case .secureRasterized: return "\(base)-secure-flattened.pdf"
        }
    }

    func exportDocument(kind: PDFExportKind) -> PDFFileDocument? {
        guard let data = dataRepresentation(kind: kind) else { return nil }
        return PDFFileDocument(data: data)
    }

    func saveInsideApp(kind: PDFExportKind) {
        do {
            guard let data = dataRepresentation(kind: kind) else {
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
            let destination = uniqueDestination(in: savedFolder, filename: exportFilename(kind: kind))
            try data.write(to: destination, options: .atomic)

            presentMessage("Saved inside Next PDF Pro. Open Files > On My iPhone > Next PDF > Saved PDFs.\n\n\(destination.lastPathComponent)")
        } catch {
            present(error: error)
        }
    }

    func makeShareFile(kind: PDFExportKind) -> URL? {
        do {
            guard let data = dataRepresentation(kind: kind) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NextPDF-Share", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(exportFilename(kind: kind))
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

    func showDocumentInformation() {
        guard let document else { return }
        let attributes = document.documentAttributes ?? [:]
        let title = attributes[PDFDocumentAttribute.titleAttribute] as? String ?? documentTitle
        let author = attributes[PDFDocumentAttribute.authorAttribute] as? String ?? "Not specified"
        let locked = document.isLocked ? "Yes" : "No"
        presentMessage("Title: \(title)\nAuthor: \(author)\nPages: \(document.pageCount)\nLocked: \(locked)\n\nEditable text replacement works on selectable PDF text. Secure Flattened export permanently burns visible edits and redactions into page images.")
    }

    // MARK: Undo and redo

    func undo() {
        guard let action = undoStack.popLast() else { return }
        action.undo()
        redoStack.append(action)
        refreshUndoState()
        refreshDocumentState()
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        action.redo()
        undoStack.append(action)
        refreshUndoState()
        refreshDocumentState()
    }

    // MARK: Alerts

    func present(error: Error) {
        alertMessage = error.localizedDescription
        showingAlert = true
    }

    func presentMessage(_ message: String) {
        alertMessage = message
        showingAlert = true
    }

    // MARK: Private helpers

    private var currentPageIndex: Int {
        guard let document,
              let page = pdfView?.currentPage,
              document.index(for: page) != NSNotFound else { return 0 }
        return document.index(for: page)
    }

    private func makeFreeTextAnnotation(text: String, bounds: CGRect, style: PDFTextStyle) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = UIFont(name: style.fontName, size: style.fontSize) ?? UIFont.systemFont(ofSize: style.fontSize)
        annotation.fontColor = style.textColor
        annotation.color = .clear
        annotation.alignment = style.alignment
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        annotation.shouldDisplay = true
        annotation.shouldPrint = true
        return annotation
    }

    private func makeCoverAnnotation(bounds: CGRect, color: UIColor) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
        annotation.color = .clear
        annotation.interiorColor = color
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        annotation.shouldDisplay = true
        annotation.shouldPrint = true
        return annotation
    }

    private func registerAnnotationBatch(_ annotations: [PDFAnnotation], on page: PDFPage) {
        registerUndo(
            undo: { [weak self, weak page] in
                guard let page else { return }
                annotations.forEach { page.removeAnnotation($0) }
                self?.clearAnnotationSelection()
                self?.refreshDisplay()
            },
            redo: { [weak self, weak page] in
                guard let page else { return }
                annotations.forEach { page.addAnnotation($0) }
                if let last = annotations.last { self?.select(annotation: last, on: page) }
                self?.refreshDisplay()
            }
        )
    }

    private func registerMultiPageAnnotations(_ records: [(PDFPage, PDFAnnotation)]) {
        registerUndo(
            undo: { [weak self] in
                records.forEach { $0.0.removeAnnotation($0.1) }
                self?.clearAnnotationSelection()
                self?.refreshDisplay()
            },
            redo: { [weak self] in
                records.forEach { $0.0.addAnnotation($0.1) }
                if let last = records.last { self?.select(annotation: last.1, on: last.0) }
                self?.refreshDisplay()
            }
        )
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

    private func refreshSelectionState() {
        let text = pdfView?.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        hasTextSelection = !text.isEmpty
    }

    private func refreshPageState() {
        pageCount = document?.pageCount ?? 0
        currentPageNumber = min(max(currentPageIndex + 1, 1), max(pageCount, 1))
    }

    private func refreshDocumentState() {
        refreshPageState()
        refreshSelectionState()
        objectWillChange.send()
        pdfView?.setNeedsLayout()
        pdfView?.setNeedsDisplay()
    }

    private func refreshDisplay() {
        objectWillChange.send()
        pdfView?.setNeedsDisplay()
    }

    private func clearTextSelection() {
        pdfView?.clearSelection()
        refreshSelectionState()
    }

    private func select(annotation: PDFAnnotation, on page: PDFPage) {
        selectedAnnotation = annotation
        selectedAnnotationPage = page
        hasSelectedAnnotation = true
        selectedAnnotationName = readableName(for: annotation)
    }

    private func clearAnnotationSelection() {
        selectedAnnotation = nil
        selectedAnnotationPage = nil
        hasSelectedAnnotation = false
        selectedAnnotationName = "Annotation"
    }

    private func readableName(for annotation: PDFAnnotation) -> String {
        switch annotation.type {
        case PDFAnnotationSubtype.freeText.rawValue: return "Text box selected"
        case PDFAnnotationSubtype.ink.rawValue: return "Ink selected"
        case PDFAnnotationSubtype.highlight.rawValue: return "Highlight selected"
        case PDFAnnotationSubtype.underline.rawValue: return "Underline selected"
        case PDFAnnotationSubtype.strikeOut.rawValue: return "Strikeout selected"
        case PDFAnnotationSubtype.square.rawValue: return "Shape selected"
        case PDFAnnotationSubtype.circle.rawValue: return "Shape selected"
        default: return "Annotation selected"
        }
    }

    private func resetMoveState() {
        moveStartPoint = nil
        moveStartBounds = nil
        movePage = nil
    }

    private func normalizedRotation(_ value: Int) -> Int {
        let result = value % 360
        return result < 0 ? result + 360 : result
    }

    private func uniqueDestination(in folder: URL, filename: String) -> URL {
        let baseURL = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return baseURL }
        let name = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return folder.appendingPathComponent("\(name)-\(formatter.string(from: Date())).\(ext)")
    }

    private func dataRepresentation(kind: PDFExportKind) -> Data? {
        switch kind {
        case .editable:
            return document?.dataRepresentation()
        case .secureRasterized:
            return secureRasterizedData()
        }
    }

    private func secureRasterizedData() -> Data? {
        guard let document, document.pageCount > 0 else { return nil }
        let defaultBounds = document.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: defaultBounds)
        return renderer.pdfData { context in
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                let image = renderPageImage(page, scale: 2.0)
                image.draw(in: bounds)
            }
        }
    }

    private func renderPageImage(_ page: PDFPage, scale: CGFloat) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))

            let cg = context.cgContext
            cg.saveGState()
            cg.translateBy(x: -bounds.minX, y: bounds.height + bounds.minY)
            cg.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: cg)
            for annotation in page.annotations {
                annotation.draw(with: .mediaBox, in: cg)
            }
            cg.restoreGState()
        }
    }
}

// MARK: - File export wrapper

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
