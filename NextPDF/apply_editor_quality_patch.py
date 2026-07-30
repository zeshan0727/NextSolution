#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
MODEL = ROOT / "NextPDF" / "PDFEditorModel.swift"
EDITOR = ROOT / "NextPDF" / "PDFKitEditorView.swift"
LIBRARY = ROOT / "NextPDF" / "PDFLibraryRootView.swift"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def patch_model() -> None:
    text = MODEL.read_text(encoding="utf-8")

    text = replace_once(
        text,
        "import UIKit\nimport PDFKit\n",
        "import UIKit\nimport PDFKit\nimport CoreText\n",
        "CoreText import",
    )

    old_detection = '''        var detectedFont = UIFont.systemFont(ofSize: max(10, bounds.height * 0.72))
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
'''

    new_detection = '''        let detected = dominantTextStyle(
            from: selection.attributedString,
            fallbackBounds: bounds
        )

        return TextEditDraft(
            pageIndex: document.index(for: page),
            bounds: bounds,
            originalText: text,
            detectedFontName: detected.font.fontName,
            detectedFontSize: detected.font.pointSize,
            detectedTextColor: detected.color,
            detectedAlignment: detected.alignment
        )
'''
    text = replace_once(text, old_detection, new_detection, "dominant original text style detection")

    old_replace = '''    func replaceText(draft: TextEditDraft, with newText: String, style: PDFTextStyle) {
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
'''

    new_replace = '''    func replaceText(draft: TextEditDraft, with newText: String, style: PDFTextStyle) {
        guard let page = document?.page(at: draft.pageIndex) else { return }

        // Expand the cover enough to hide the original glyph ascenders, descenders
        // and antialiasing. A transparent square border can leave old text visible,
        // so the cover uses the same solid colour for its stroke and interior.
        let verticalPadding = max(2.0, draft.bounds.height * 0.16)
        let coverBounds = draft.bounds.insetBy(dx: -2.5, dy: -verticalPadding)
        let cover = makeCoverAnnotation(bounds: coverBounds, color: style.coverColor)
        page.addAnnotation(cover)

        var annotations: [PDFAnnotation] = [cover]
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            let font = replacementFont(named: style.fontName, size: style.fontSize)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = style.alignment
            paragraph.lineBreakMode = .byWordWrapping

            let pageBounds = page.bounds(for: .cropBox)
            let availableWidth = max(24, pageBounds.maxX - draft.bounds.minX - 6)
            let measured = (trimmed as NSString).boundingRect(
                with: CGSize(width: availableWidth, height: 2_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [
                    .font: font,
                    .paragraphStyle: paragraph
                ],
                context: nil
            ).integral

            let targetWidth = min(
                availableWidth,
                max(draft.bounds.width, measured.width + 5)
            )
            let targetHeight = max(
                draft.bounds.height + 2,
                measured.height + 3,
                font.lineHeight + 2
            )
            let verticalGrowth = max(0, targetHeight - draft.bounds.height)
            let textBounds = CGRect(
                x: draft.bounds.minX,
                y: draft.bounds.minY - verticalGrowth * 0.34,
                width: max(targetWidth, 12),
                height: targetHeight
            )

            var matchedStyle = style
            matchedStyle.fontName = font.fontName
            matchedStyle.fontSize = font.pointSize
            let replacement = makeFreeTextAnnotation(text: trimmed, bounds: textBounds, style: matchedStyle)
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
'''
    text = replace_once(text, old_replace, new_replace, "matched text replacement geometry")

    helper_marker = '''    private func makeFreeTextAnnotation(text: String, bounds: CGRect, style: PDFTextStyle) -> PDFAnnotation {'''
    helper_code = '''    private func dominantTextStyle(
        from attributed: NSAttributedString?,
        fallbackBounds: CGRect
    ) -> (font: UIFont, color: UIColor, alignment: NSTextAlignment) {
        let fallbackSize = min(144, max(8, fallbackBounds.height * 0.72))
        var dominantFont: UIFont?
        var dominantFontLength = 0
        var dominantColor: UIColor = .label
        var dominantColorLength = 0
        var alignment: NSTextAlignment = .left

        if let attributed, attributed.length > 0 {
            let fullRange = NSRange(location: 0, length: attributed.length)

            attributed.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                guard range.length >= dominantFontLength,
                      let candidate = uiFont(from: value) else { return }
                dominantFont = candidate
                dominantFontLength = range.length
            }

            attributed.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
                guard range.length >= dominantColorLength,
                      let candidate = value as? UIColor else { return }
                dominantColor = candidate
                dominantColorLength = range.length
            }

            if let paragraph = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                alignment = paragraph.alignment
            }
        }

        let font = resolvedDetectedFont(dominantFont, fallbackSize: fallbackSize)
        return (font, dominantColor, alignment)
    }

    private func uiFont(from value: Any?) -> UIFont? {
        if let font = value as? UIFont { return font }
        guard let value else { return nil }
        let reference = value as CFTypeRef
        guard CFGetTypeID(reference) == CTFontGetTypeID() else { return nil }
        let ctFont = unsafeBitCast(reference, to: CTFont.self)
        let name = CTFontCopyPostScriptName(ctFont) as String
        return UIFont(name: name, size: CTFontGetSize(ctFont))
    }

    private func resolvedDetectedFont(_ detected: UIFont?, fallbackSize: CGFloat) -> UIFont {
        guard let detected else {
            return UIFont.systemFont(ofSize: fallbackSize)
        }

        let pointSize = (5...180).contains(detected.pointSize) ? detected.pointSize : fallbackSize
        if let exact = UIFont(name: detected.fontName, size: pointSize) {
            return exact
        }

        let strippedName = stripEmbeddedSubsetPrefix(detected.fontName)
        if let stripped = UIFont(name: strippedName, size: pointSize) {
            return stripped
        }

        let traits = detected.fontDescriptor.symbolicTraits
        let familyDescriptor = UIFontDescriptor(fontAttributes: [
            .family: stripEmbeddedSubsetPrefix(detected.familyName)
        ])
        if let descriptor = familyDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: pointSize)
        }

        return replacementFont(named: detected.fontName, size: pointSize)
    }

    private func stripEmbeddedSubsetPrefix(_ name: String) -> String {
        guard let plus = name.firstIndex(of: "+") else { return name }
        let prefix = name[..<plus]
        guard prefix.count == 6,
              prefix.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else {
            return name
        }
        return String(name[name.index(after: plus)...])
    }

    private func replacementFont(named requestedName: String, size requestedSize: CGFloat) -> UIFont {
        let size = min(180, max(6, requestedSize))
        if let exact = UIFont(name: requestedName, size: size) { return exact }

        let stripped = stripEmbeddedSubsetPrefix(requestedName)
        if let exact = UIFont(name: stripped, size: size) { return exact }

        let lower = stripped.lowercased()
        let weight: UIFont.Weight
        if lower.contains("black") || lower.contains("heavy") {
            weight = .heavy
        } else if lower.contains("bold") || lower.contains("demi") {
            weight = .bold
        } else if lower.contains("semibold") || lower.contains("semi-bold") {
            weight = .semibold
        } else if lower.contains("medium") {
            weight = .medium
        } else if lower.contains("light") || lower.contains("thin") {
            weight = .light
        } else {
            weight = .regular
        }

        var font = UIFont.systemFont(ofSize: size, weight: weight)
        if lower.contains("italic") || lower.contains("oblique") {
            let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: size)
            }
        }
        return font
    }

'''
    if helper_marker not in text:
        raise RuntimeError("font helper insertion marker not found")
    text = text.replace(helper_marker, helper_code + helper_marker, 1)

    old_annotations = '''    private func makeFreeTextAnnotation(text: String, bounds: CGRect, style: PDFTextStyle) -> PDFAnnotation {
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
'''

    new_annotations = '''    private func makeFreeTextAnnotation(text: String, bounds: CGRect, style: PDFTextStyle) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        let font = replacementFont(named: style.fontName, size: style.fontSize)
        annotation.contents = text
        annotation.font = font
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
        annotation.color = color
        annotation.interiorColor = color
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        annotation.shouldDisplay = true
        annotation.shouldPrint = true
        return annotation
    }
'''
    text = replace_once(text, old_annotations, new_annotations, "solid cover and resolved free-text font")

    old_saved_folder = '''            let savedFolder = documentsDirectory.appendingPathComponent("Saved PDFs", isDirectory: true)
            try FileManager.default.createDirectory(at: savedFolder, withIntermediateDirectories: true)
            let destination = uniqueDestination(in: savedFolder, filename: exportFilename(kind: kind))
'''
    new_saved_folder = '''            let libraryRoot = documentsDirectory.appendingPathComponent("PDF Library", isDirectory: true)
            let savedFolder = libraryRoot.appendingPathComponent("Saved PDFs", isDirectory: true)
            try FileManager.default.createDirectory(at: savedFolder, withIntermediateDirectories: true)
            let destination = uniqueDestination(in: savedFolder, filename: exportFilename(kind: kind))
'''
    text = replace_once(text, old_saved_folder, new_saved_folder, "save into visible PDF Library/Saved PDFs")

    old_message = '''            presentMessage("Saved inside Next PDF Pro. Open Files > On My iPhone > Next PDF > Saved PDFs.\\n\\n\\(destination.lastPathComponent)")'''
    new_message = '''            presentMessage("Saved inside Next PDF Pro. Open Files > On My iPhone > Next PDF > PDF Library > Saved PDFs.\\n\\n\\(destination.lastPathComponent)")'''
    text = replace_once(text, old_message, new_message, "updated Files save location message")

    MODEL.write_text(text, encoding="utf-8")


def patch_editor() -> None:
    text = EDITOR.read_text(encoding="utf-8")

    old_pan = '''        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleAnnotationPan(_:)))
        pan.cancelsTouchesInView = false
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
'''
    new_pan = '''        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleAnnotationPan(_:)))
        pan.cancelsTouchesInView = true
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.annotationPan = pan
'''
    text = replace_once(text, old_pan, new_pan, "annotation pan ownership")

    old_properties = '''        private weak var pdfView: PDFView?
        private var observingView: PDFView?
'''
    new_properties = '''        private weak var pdfView: PDFView?
        private var observingView: PDFView?
        weak var annotationPan: UIPanGestureRecognizer?
        private var lockedScrollViews: [(scroll: UIScrollView, wasEnabled: Bool)] = []
'''
    text = replace_once(text, old_properties, new_properties, "annotation drag coordinator state")

    old_attach_end = '''            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged),
                name: Notification.Name.PDFViewPageChanged,
                object: view
            )
        }
'''
    new_attach_end = '''            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged),
                name: Notification.Name.PDFViewPageChanged,
                object: view
            )
            configureGesturePriority(in: view)
        }
'''
    text = replace_once(text, old_attach_end, new_attach_end, "annotation gesture priority setup")

    old_detach_tail = '''            observingView = nil
            pdfView = nil
        }
'''
    new_detach_tail = '''            unlockDocumentNavigation()
            observingView = nil
            pdfView = nil
        }
'''
    text = replace_once(text, old_detach_tail, new_detach_tail, "restore scrolling during detach")

    old_handlers = '''        @objc func handleAnnotationPan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = pdfView else { return }
            let point = recognizer.location(in: view)
            Task { @MainActor in
                switch recognizer.state {
                case .began:
                    model.beginMovingSelectedAnnotation(at: point, in: view)
                case .changed:
                    model.moveSelectedAnnotation(to: point, in: view)
                case .ended, .cancelled, .failed:
                    model.endMovingSelectedAnnotation()
                default:
                    break
                }
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
'''

    new_handlers = '''        @objc func handleAnnotationPan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = pdfView else { return }
            let point = recognizer.location(in: view)

            switch recognizer.state {
            case .began:
                // Once an annotation drag wins, freeze every PDFKit scroll view.
                // This prevents the page and the signature/stamp moving together.
                lockDocumentNavigation(in: view)
                Task { @MainActor in
                    model.handleTap(at: point, in: view)
                    model.beginMovingSelectedAnnotation(at: point, in: view)
                }
            case .changed:
                Task { @MainActor in
                    model.moveSelectedAnnotation(to: point, in: view)
                }
            case .ended, .cancelled, .failed:
                Task { @MainActor in
                    model.endMovingSelectedAnnotation()
                }
                unlockDocumentNavigation()
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === annotationPan,
                  let view = pdfView else { return true }

            let viewPoint = gestureRecognizer.location(in: view)
            guard let page = view.page(for: viewPoint, nearest: false) else { return false }
            let pagePoint = view.convert(viewPoint, to: page)

            // The custom pan only begins over an annotation. Everywhere else it
            // fails immediately and normal PDF scrolling/zooming remains available.
            return page.annotations.reversed().contains { annotation in
                annotation.shouldDisplay &&
                annotation.bounds.insetBy(dx: -14, dy: -14).contains(pagePoint)
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer === annotationPan || otherGestureRecognizer === annotationPan {
                return false
            }
            return true
        }

        private func configureGesturePriority(in view: UIView) {
            guard let annotationPan else { return }
            // Give annotation dragging the first chance. If the touch is not on an
            // annotation, gestureRecognizerShouldBegin returns false and scrolling starts.
            for scrollView in allScrollViews(in: view) {
                scrollView.panGestureRecognizer.require(toFail: annotationPan)
            }
        }

        private func lockDocumentNavigation(in view: UIView) {
            guard lockedScrollViews.isEmpty else { return }
            lockedScrollViews = allScrollViews(in: view).map { scrollView in
                let state = scrollView.isScrollEnabled
                scrollView.isScrollEnabled = false
                return (scrollView, state)
            }
        }

        private func unlockDocumentNavigation() {
            for entry in lockedScrollViews {
                entry.scroll.isScrollEnabled = entry.wasEnabled
            }
            lockedScrollViews.removeAll()
        }

        private func allScrollViews(in view: UIView) -> [UIScrollView] {
            var result: [UIScrollView] = []
            if let scrollView = view as? UIScrollView {
                result.append(scrollView)
            }
            for subview in view.subviews {
                result.append(contentsOf: allScrollViews(in: subview))
            }
            return result
        }
'''
    text = replace_once(text, old_handlers, new_handlers, "lock page while moving annotations")

    EDITOR.write_text(text, encoding="utf-8")


def patch_library() -> None:
    text = LIBRARY.read_text(encoding="utf-8")

    old_folders = '''    private func managedFolders(createPrimary: Bool) throws -> [URL] {
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
                destination = library.appendingPathComponent("\\(base) \\(suffix)").appendingPathExtension("pdf")
                suffix += 1
            }

            // Import only copies bytes into local app storage. No PDFKit parsing,
            // text extraction or OCR is performed here.
            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        }.value
    }
'''

    new_folders = '''    private func managedFolders(createPrimary: Bool) throws -> [URL] {
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = documents.appendingPathComponent("PDF Library", isDirectory: true)
        let imported = root.appendingPathComponent("Imported PDFs", isDirectory: true)
        let saved = root.appendingPathComponent("Saved PDFs", isDirectory: true)

        if createPrimary {
            try fileManager.createDirectory(at: imported, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: saved, withIntermediateDirectories: true)
            try migrateLegacyPDFs(documents: documents, root: root, imported: imported, saved: saved)
            try createFilesVisibilityMarker(in: root)
        }

        return [imported, saved]
    }

    private func migrateLegacyPDFs(
        documents: URL,
        root: URL,
        imported: URL,
        saved: URL
    ) throws {
        try movePDFs(
            from: documents.appendingPathComponent("Saved PDFs", isDirectory: true),
            to: saved
        )
        try movePDFs(
            from: documents.appendingPathComponent("Imported PDFs", isDirectory: true),
            to: imported
        )

        // Earlier builds stored imported files directly inside PDF Library.
        // Move those PDFs into the new Imported PDFs subfolder.
        if fileManager.fileExists(atPath: root.path) {
            let rootItems = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            for source in rootItems where source.pathExtension.lowercased() == "pdf" {
                let destination = uniqueDestination(in: imported, filename: source.lastPathComponent)
                try fileManager.moveItem(at: source, to: destination)
            }
        }
    }

    private func movePDFs(from sourceFolder: URL, to destinationFolder: URL) throws {
        guard fileManager.fileExists(atPath: sourceFolder.path) else { return }
        let items = try fileManager.contentsOfDirectory(
            at: sourceFolder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for source in items where source.pathExtension.lowercased() == "pdf" {
            let destination = uniqueDestination(in: destinationFolder, filename: source.lastPathComponent)
            try fileManager.moveItem(at: source, to: destination)
        }
        if (try? fileManager.contentsOfDirectory(atPath: sourceFolder.path).isEmpty) == true {
            try? fileManager.removeItem(at: sourceFolder)
        }
    }

    private func uniqueDestination(in folder: URL, filename: String) -> URL {
        let source = URL(fileURLWithPath: filename)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.isEmpty ? "pdf" : source.pathExtension
        var destination = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\\(base) \\(suffix)").appendingPathExtension(ext)
            suffix += 1
        }
        return destination
    }

    private func createFilesVisibilityMarker(in root: URL) throws {
        let marker = root.appendingPathComponent("NextPDF Library Information.txt")
        guard !fileManager.fileExists(atPath: marker.path) else { return }
        let message = """
        This folder is managed by Next PDF.

        Imported PDFs are stored in: Imported PDFs
        PDFs saved from the editor are stored in: Saved PDFs
        """
        try message.data(using: .utf8)?.write(to: marker, options: .atomic)
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
            let root = documents.appendingPathComponent("PDF Library", isDirectory: true)
            let imported = root.appendingPathComponent("Imported PDFs", isDirectory: true)
            try fileManager.createDirectory(at: imported, withIntermediateDirectories: true)

            let originalBase = sourceURL.deletingPathExtension().lastPathComponent
            let base = originalBase.isEmpty ? "Imported PDF" : originalBase
            var destination = imported.appendingPathComponent(base).appendingPathExtension("pdf")
            var suffix = 2
            while fileManager.fileExists(atPath: destination.path) {
                destination = imported.appendingPathComponent("\\(base) \\(suffix)").appendingPathExtension("pdf")
                suffix += 1
            }

            // Import only copies bytes into local app storage. No PDFKit parsing,
            // text extraction or OCR is performed here.
            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        }.value
    }
'''
    text = replace_once(text, old_folders, new_folders, "visible nested PDF library and legacy migration")

    old_title = '''            .navigationTitle("PDF Library")
            .searchable(text: $searchText, prompt: "Search PDFs")
'''
    new_title = '''            .navigationTitle("PDF Library")
            .onAppear {
                store.reload()
            }
            .searchable(text: $searchText, prompt: "Search PDFs")
'''
    text = replace_once(text, old_title, new_title, "refresh saved PDFs when Library tab opens")

    LIBRARY.write_text(text, encoding="utf-8")


def main() -> int:
    try:
        patch_model()
        patch_editor()
        patch_library()
        print("Applied NextPDF matched text, Files library, and locked annotation dragging")
        return 0
    except Exception as exc:
        print(f"Editor quality patch failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
