#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
MODEL = ROOT / "NextPDF" / "PDFEditorModel.swift"
EDITOR = ROOT / "NextPDF" / "PDFKitEditorView.swift"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def replace_regex_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one regex match, found {count}")
    return updated


def patch_model() -> None:
    text = MODEL.read_text(encoding="utf-8")

    old_draft = '''struct TextEditDraft: Identifiable {
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
'''
    new_draft = '''struct TextEditDraft: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let bounds: CGRect
    let originalText: String
    let detectedFontName: String
    let detectedFontSize: CGFloat
    let detectedTextColor: UIColor
    let detectedAlignment: NSTextAlignment

    // Full visual line context. Rebuilding the complete line prevents the old
    // suffix or prefix from remaining visible behind a short replacement.
    let lineBounds: CGRect
    let lineText: String
    let lineAttributedText: NSAttributedString?
    let selectedRangeInLine: NSRange

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
'''
    text = replace_once(text, old_draft, new_draft, "full-line text draft context")

    old_move_state = '''    private var moveStartPoint: CGPoint?
    private var moveStartBounds: CGRect?
    private weak var movePage: PDFPage?
'''
    new_move_state = '''    private var moveStartPoint: CGPoint?
    private var moveStartBounds: CGRect?
    private weak var movePage: PDFPage?

    private var resizeStartBounds: CGRect?
    private weak var resizePage: PDFPage?
'''
    text = replace_once(text, old_move_state, new_move_state, "annotation resize state")

    bounds_guard = '''        let bounds = selection.bounds(for: page).standardized
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }

        let detected = dominantTextStyle(
'''
    bounds_guard_replacement = '''        let bounds = selection.bounds(for: page).standardized
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }

        let lineContext = fullLineContext(
            around: selection,
            selectedText: text,
            selectedBounds: bounds,
            on: page
        )

        let detected = dominantTextStyle(
'''
    text = replace_once(text, bounds_guard, bounds_guard_replacement, "capture full PDF line")

    old_return = '''        return TextEditDraft(
            pageIndex: document.index(for: page),
            bounds: bounds,
            originalText: text,
            detectedFontName: detected.font.fontName,
            detectedFontSize: detected.font.pointSize,
            detectedTextColor: detected.color,
            detectedAlignment: detected.alignment
        )
'''
    new_return = '''        return TextEditDraft(
            pageIndex: document.index(for: page),
            bounds: bounds,
            originalText: text,
            detectedFontName: detected.font.fontName,
            detectedFontSize: detected.font.pointSize,
            detectedTextColor: detected.color,
            detectedAlignment: detected.alignment,
            lineBounds: lineContext.bounds,
            lineText: lineContext.text,
            lineAttributedText: lineContext.attributed,
            selectedRangeInLine: lineContext.selectedRange
        )
'''
    text = replace_once(text, old_return, new_return, "store line reconstruction data")

    replacement_method = '''    func replaceText(draft: TextEditDraft, with newText: String, style: PDFTextStyle) {
        guard let page = document?.page(at: draft.pageIndex) else { return }

        let replacementText = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rebuilt = rebuiltLineAttributedString(
            draft: draft,
            replacementText: replacementText,
            style: style
        )

        // Hide the complete original line, not only the selected word bounds.
        // This guarantees that a longer or shorter replacement cannot leave old
        // glyphs visible to its right or underneath it.
        let lineBounds = draft.lineBounds.isNull || draft.lineBounds.isEmpty
            ? draft.bounds
            : draft.lineBounds
        let paddingX = max(3.0, lineBounds.height * 0.18)
        let paddingY = max(2.5, lineBounds.height * 0.22)
        let coverBounds = lineBounds.insetBy(dx: -paddingX, dy: -paddingY)
        let cover = makeCoverAnnotation(bounds: coverBounds, color: style.coverColor)
        cover.userName = "NextPDFTextCover"
        page.addAnnotation(cover)

        var annotations: [PDFAnnotation] = [cover]
        if rebuilt.length > 0 {
            let rebuiltAnnotations = makeRebuiltLineAnnotations(
                from: rebuilt,
                lineBounds: lineBounds,
                on: page,
                fallbackStyle: style
            )
            for annotation in rebuiltAnnotations {
                page.addAnnotation(annotation)
            }
            annotations.append(contentsOf: rebuiltAnnotations)
            if let last = rebuiltAnnotations.last {
                select(annotation: last, on: page)
            } else {
                select(annotation: cover, on: page)
            }
        } else {
            select(annotation: cover, on: page)
        }

        registerAnnotationBatch(annotations, on: page)
        clearTextSelection()
        refreshDisplay()
    }

'''
    text = replace_regex_once(
        text,
        r'''    func replaceText\(draft: TextEditDraft, with newText: String, style: PDFTextStyle\) \{.*?\n    \}\n\n    func removeSelectedText''',
        replacement_method + '''    func removeSelectedText''',
        "replace complete visual line instead of layering selected text",
    )

    helper_marker = '''    private func dominantTextStyle(
'''
    helper_code = '''    private func fullLineContext(
        around selection: PDFSelection,
        selectedText: String,
        selectedBounds: CGRect,
        on page: PDFPage
    ) -> (bounds: CGRect, text: String, attributed: NSAttributedString?, selectedRange: NSRange) {
        let pageBounds = page.bounds(for: .cropBox)
        let verticalPadding = max(3.0, selectedBounds.height * 0.58)
        let band = CGRect(
            x: pageBounds.minX,
            y: selectedBounds.minY - verticalPadding,
            width: pageBounds.width,
            height: selectedBounds.height + verticalPadding * 2
        ).intersection(pageBounds)

        let candidates = page.selection(for: band)?.selectionsByLine() ?? []
        let lineSelection = candidates.min { left, right in
            let leftBounds = left.bounds(for: page).standardized
            let rightBounds = right.bounds(for: page).standardized
            return abs(leftBounds.midY - selectedBounds.midY) < abs(rightBounds.midY - selectedBounds.midY)
        } ?? selection

        let detectedBounds = lineSelection.bounds(for: page).standardized
        let lineBounds = detectedBounds.isNull || detectedBounds.isEmpty ? selectedBounds : detectedBounds
        let rawText = lineSelection.string ?? selectedText
        let lineText = rawText.trimmingCharacters(in: .newlines)
        let attributed = lineSelection.attributedString
        let selectedRange = bestSelectedRange(
            selectedText: selectedText,
            in: lineText,
            selectedBounds: selectedBounds,
            lineBounds: lineBounds
        )

        return (lineBounds, lineText, attributed, selectedRange)
    }

    private func bestSelectedRange(
        selectedText: String,
        in lineText: String,
        selectedBounds: CGRect,
        lineBounds: CGRect
    ) -> NSRange {
        let line = lineText as NSString
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty, line.length > 0 else {
            return NSRange(location: 0, length: line.length)
        }

        var candidates: [NSRange] = []
        var searchRange = NSRange(location: 0, length: line.length)
        while searchRange.length > 0 {
            let found = line.range(of: selected, options: [], range: searchRange)
            if found.location == NSNotFound { break }
            candidates.append(found)
            let next = found.location + max(found.length, 1)
            if next >= line.length { break }
            searchRange = NSRange(location: next, length: line.length - next)
        }

        if candidates.isEmpty {
            let found = line.range(of: selected, options: [.caseInsensitive])
            if found.location != NSNotFound { candidates.append(found) }
        }

        guard !candidates.isEmpty else {
            return NSRange(location: NSNotFound, length: 0)
        }
        guard candidates.count > 1, lineBounds.width > 0 else { return candidates[0] }

        let ratio = min(1, max(0, (selectedBounds.midX - lineBounds.minX) / lineBounds.width))
        let estimatedCharacter = CGFloat(line.length) * ratio
        return candidates.min { left, right in
            let leftMid = CGFloat(left.location) + CGFloat(left.length) / 2
            let rightMid = CGFloat(right.location) + CGFloat(right.length) / 2
            return abs(leftMid - estimatedCharacter) < abs(rightMid - estimatedCharacter)
        } ?? candidates[0]
    }

    private func rebuiltLineAttributedString(
        draft: TextEditDraft,
        replacementText: String,
        style: PDFTextStyle
    ) -> NSMutableAttributedString {
        let defaultFont = replacementFont(named: draft.detectedFontName, size: draft.detectedFontSize)
        let defaultParagraph = NSMutableParagraphStyle()
        defaultParagraph.alignment = draft.detectedAlignment

        let rebuilt: NSMutableAttributedString
        if let attributed = draft.lineAttributedText, attributed.length > 0 {
            rebuilt = NSMutableAttributedString(attributedString: attributed)
        } else {
            rebuilt = NSMutableAttributedString(
                string: draft.lineText,
                attributes: [
                    .font: defaultFont,
                    .foregroundColor: draft.detectedTextColor,
                    .paragraphStyle: defaultParagraph
                ]
            )
        }

        // Remove only line terminators introduced by PDFKit's line selection.
        while rebuilt.length > 0 {
            let final = (rebuilt.string as NSString).substring(
                with: NSRange(location: rebuilt.length - 1, length: 1)
            )
            if final == "\\n" || final == "\\r" {
                rebuilt.deleteCharacters(in: NSRange(location: rebuilt.length - 1, length: 1))
            } else {
                break
            }
        }

        var selectedRange = draft.selectedRangeInLine
        if selectedRange.location == NSNotFound || NSMaxRange(selectedRange) > rebuilt.length {
            selectedRange = bestSelectedRange(
                selectedText: draft.originalText,
                in: rebuilt.string,
                selectedBounds: draft.bounds,
                lineBounds: draft.lineBounds
            )
        }

        let replacementFontValue = replacementFont(named: style.fontName, size: style.fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = style.alignment
        paragraph.lineBreakMode = .byClipping
        let replacement = NSAttributedString(
            string: replacementText,
            attributes: [
                .font: replacementFontValue,
                .foregroundColor: style.textColor,
                .paragraphStyle: paragraph
            ]
        )

        if selectedRange.location != NSNotFound, NSMaxRange(selectedRange) <= rebuilt.length {
            rebuilt.replaceCharacters(in: selectedRange, with: replacement)
        } else {
            // A malformed text map is uncommon, but replacing the complete selected
            // line is still safer than placing another layer over unknown old glyphs.
            rebuilt.setAttributedString(replacement)
        }
        return rebuilt
    }

    private func makeRebuiltLineAnnotations(
        from attributed: NSAttributedString,
        lineBounds: CGRect,
        on page: PDFPage,
        fallbackStyle: PDFTextStyle
    ) -> [PDFAnnotation] {
        guard attributed.length > 0 else { return [] }

        let pageBounds = page.bounds(for: .cropBox)
        var annotations: [PDFAnnotation] = []
        var cursorX = lineBounds.minX

        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { attributes, range, _ in
            var runText = (attributed.string as NSString).substring(with: range)
            runText = runText.replacingOccurrences(of: "\\n", with: "")
                .replacingOccurrences(of: "\\r", with: "")
            guard !runText.isEmpty, cursorX < pageBounds.maxX - 2 else { return }

            let font = uiFont(from: attributes[.font])
                .map { resolvedDetectedFont($0, fallbackSize: fallbackStyle.fontSize) }
                ?? replacementFont(named: fallbackStyle.fontName, size: fallbackStyle.fontSize)
            let color = attributes[.foregroundColor] as? UIColor ?? fallbackStyle.textColor
            let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
            let measured = (runText as NSString).size(withAttributes: [.font: font])
            let width = min(
                max(3, measured.width + 1.5),
                max(3, pageBounds.maxX - cursorX - 2)
            )
            let height = max(lineBounds.height * 1.34, font.lineHeight * 1.28)
            let y = lineBounds.minY - max(1, (height - lineBounds.height) * 0.30)

            let runStyle = PDFTextStyle(
                fontName: font.fontName,
                fontSize: font.pointSize,
                textColor: color,
                coverColor: fallbackStyle.coverColor,
                alignment: paragraph?.alignment ?? .left
            )
            let annotation = makeFreeTextAnnotation(
                text: runText,
                bounds: CGRect(x: cursorX, y: y, width: width, height: height),
                style: runStyle
            )
            annotation.userName = "NextPDFRebuiltText"
            annotations.append(annotation)
            cursorX += measured.width
        }

        return annotations
    }

'''
    if helper_marker not in text:
        raise RuntimeError("line reconstruction helper marker not found")
    text = text.replace(helper_marker, helper_code + helper_marker, 1)

    old_hit_test = '''        let found = page.annotations.reversed().first { annotation in
            annotation.bounds.insetBy(dx: -8, dy: -8).contains(pagePoint)
        }
'''
    new_hit_test = '''        let found = page.annotations.reversed().first { annotation in
            annotation.userName != "NextPDFTextCover" &&
            annotation.bounds.insetBy(dx: -8, dy: -8).contains(pagePoint)
        }
'''
    text = replace_once(text, old_hit_test, new_hit_test, "ignore internal line covers when selecting")

    resize_methods = '''    func beginResizingSelectedAnnotation(at viewPoint: CGPoint, in view: PDFView) {
        guard let annotation = selectedAnnotation,
              annotation.userName != "NextPDFTextCover",
              let page = selectedAnnotationPage,
              let touchedPage = view.page(for: viewPoint, nearest: false),
              touchedPage === page else { return }

        let pagePoint = view.convert(viewPoint, to: page)
        guard annotation.bounds.insetBy(dx: -18, dy: -18).contains(pagePoint) else { return }
        resizeStartBounds = annotation.bounds
        resizePage = page
    }

    func resizeSelectedAnnotation(scale: CGFloat) {
        guard let annotation = selectedAnnotation,
              let page = resizePage,
              let original = resizeStartBounds,
              scale.isFinite,
              scale > 0 else { return }

        let pageBounds = page.bounds(for: .cropBox)
        let ratio = original.height > 0 ? original.width / original.height : 1
        let minWidth: CGFloat = annotation.type == PDFAnnotationSubtype.freeText.rawValue ? 44 : 24
        let minHeight: CGFloat = annotation.type == PDFAnnotationSubtype.freeText.rawValue ? 24 : 16
        let maxWidth = max(minWidth, pageBounds.width - 8)
        let maxHeight = max(minHeight, pageBounds.height - 8)

        var width = min(maxWidth, max(minWidth, original.width * scale))
        var height = min(maxHeight, max(minHeight, original.height * scale))
        if ratio > 0 {
            if width / height > ratio {
                width = height * ratio
            } else {
                height = width / ratio
            }
        }

        var resized = CGRect(
            x: original.midX - width / 2,
            y: original.midY - height / 2,
            width: width,
            height: height
        )
        resized.origin.x = min(max(pageBounds.minX, resized.minX), pageBounds.maxX - resized.width)
        resized.origin.y = min(max(pageBounds.minY, resized.minY), pageBounds.maxY - resized.height)
        annotation.bounds = resized
        refreshDisplay()
    }

    func endResizingSelectedAnnotation() {
        guard let annotation = selectedAnnotation,
              let original = resizeStartBounds,
              let page = resizePage else {
            resetResizeState()
            return
        }

        let finalBounds = annotation.bounds
        resetResizeState()
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

    private func resetResizeState() {
        resizeStartBounds = nil
        resizePage = nil
    }

'''
    delete_marker = '''    func deleteSelectedAnnotation() {'''
    if delete_marker not in text:
        raise RuntimeError("annotation resize insertion marker not found")
    text = text.replace(delete_marker, resize_methods + delete_marker, 1)

    MODEL.write_text(text, encoding="utf-8")


def patch_editor() -> None:
    text = EDITOR.read_text(encoding="utf-8")

    pinch_setup_marker = '''        context.coordinator.annotationPan = pan
'''
    pinch_setup = '''        context.coordinator.annotationPan = pan

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleAnnotationPinch(_:))
        )
        pinch.cancelsTouchesInView = true
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        context.coordinator.annotationPinch = pinch
'''
    text = replace_once(text, pinch_setup_marker, pinch_setup, "install annotation pinch recognizer")

    old_properties = '''        weak var annotationPan: UIPanGestureRecognizer?
        private var lockedScrollViews: [(scroll: UIScrollView, wasEnabled: Bool)] = []
'''
    new_properties = '''        weak var annotationPan: UIPanGestureRecognizer?
        weak var annotationPinch: UIPinchGestureRecognizer?
        private var lockedScrollViews: [(scroll: UIScrollView, wasEnabled: Bool)] = []
'''
    text = replace_once(text, old_properties, new_properties, "store annotation pinch recognizer")

    should_begin_old = '''        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
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
'''
    should_begin_new = '''        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === annotationPan || gestureRecognizer === annotationPinch,
                  let view = pdfView else { return true }

            let viewPoint = gestureRecognizer.location(in: view)
            guard let page = view.page(for: viewPoint, nearest: false) else { return false }
            let pagePoint = view.convert(viewPoint, to: page)

            // Movement and resizing begin only over a user-visible annotation.
            // Otherwise the recognizer fails immediately and PDF scrolling/zooming wins.
            return page.annotations.reversed().contains { annotation in
                annotation.shouldDisplay &&
                annotation.userName != "NextPDFTextCover" &&
                annotation.bounds.insetBy(dx: -16, dy: -16).contains(pagePoint)
            }
        }
'''
    text = replace_once(text, should_begin_old, should_begin_new, "pinch hit testing")

    pinch_handler = '''        @objc func handleAnnotationPinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let view = pdfView else { return }
            let point = recognizer.location(in: view)

            switch recognizer.state {
            case .began:
                lockDocumentNavigation(in: view)
                Task { @MainActor in
                    model.handleTap(at: point, in: view)
                    model.beginResizingSelectedAnnotation(at: point, in: view)
                }
            case .changed:
                let scale = recognizer.scale
                Task { @MainActor in
                    model.resizeSelectedAnnotation(scale: scale)
                }
            case .ended, .cancelled, .failed:
                Task { @MainActor in
                    model.endResizingSelectedAnnotation()
                }
                unlockDocumentNavigation()
            default:
                break
            }
        }

'''
    should_begin_marker = '''        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {'''
    if should_begin_marker not in text:
        raise RuntimeError("pinch handler insertion marker not found")
    text = text.replace(should_begin_marker, pinch_handler + should_begin_marker, 1)

    simultaneous_old = '''            if gestureRecognizer === annotationPan || otherGestureRecognizer === annotationPan {
                return false
            }
'''
    simultaneous_new = '''            if gestureRecognizer === annotationPan || otherGestureRecognizer === annotationPan ||
                gestureRecognizer === annotationPinch || otherGestureRecognizer === annotationPinch {
                return false
            }
'''
    text = replace_once(text, simultaneous_old, simultaneous_new, "exclusive annotation movement and resizing")

    priority_old = '''            for scrollView in allScrollViews(in: view) {
                scrollView.panGestureRecognizer.require(toFail: annotationPan)
            }
'''
    priority_new = '''            for scrollView in allScrollViews(in: view) {
                scrollView.panGestureRecognizer.require(toFail: annotationPan)
                if let annotationPinch,
                   let documentPinch = scrollView.pinchGestureRecognizer {
                    documentPinch.require(toFail: annotationPinch)
                }
            }
'''
    text = replace_once(text, priority_old, priority_new, "annotation pinch priority over PDF zoom")

    EDITOR.write_text(text, encoding="utf-8")


def main() -> int:
    try:
        patch_model()
        patch_editor()
        print("Applied true line text replacement and annotation pinch resizing")
        return 0
    except Exception as exc:
        print(f"True text/resize patch failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
