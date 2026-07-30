#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
MODEL = ROOT / "NextPDF" / "PDFEditorModel.swift"
EDITOR = ROOT / "NextPDF" / "PDFKitEditorView.swift"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def patch_model() -> None:
    text = MODEL.read_text(encoding="utf-8")

    text = replace_once(
        text,
        '''    func attach(pdfView: PDFView) {
        self.pdfView = pdfView
        refreshSelectionState()
        refreshPageState()
    }
''',
        '''    func attach(pdfView: PDFView) {
        // UIViewRepresentable.updateUIView may run many times. Attaching the same
        // PDFView must never publish model state from inside a SwiftUI update pass.
        guard self.pdfView !== pdfView else { return }
        self.pdfView = pdfView
    }
''',
        "idempotent PDFView attachment",
    )

    text = replace_once(
        text,
        '''    private func refreshUndoState() {
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
''',
        '''    private func refreshUndoState() {
        let nextCanUndo = !undoStack.isEmpty
        let nextCanRedo = !redoStack.isEmpty
        if canUndo != nextCanUndo { canUndo = nextCanUndo }
        if canRedo != nextCanRedo { canRedo = nextCanRedo }
    }

    private func refreshSelectionState() {
        let text = pdfView?.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextValue = !text.isEmpty
        if hasTextSelection != nextValue { hasTextSelection = nextValue }
    }

    private func refreshPageState() {
        let nextPageCount = document?.pageCount ?? 0
        let nextPageNumber = min(max(currentPageIndex + 1, 1), max(nextPageCount, 1))
        if pageCount != nextPageCount { pageCount = nextPageCount }
        if currentPageNumber != nextPageNumber { currentPageNumber = nextPageNumber }
    }

    private func refreshDocumentState() {
        refreshPageState()
        refreshSelectionState()
        pdfView?.setNeedsLayout()
        pdfView?.setNeedsDisplay()
    }

    private func refreshDisplay() {
        pdfView?.setNeedsDisplay()
    }
''',
        "publish only changed editor state",
    )

    MODEL.write_text(text, encoding="utf-8")


def patch_editor() -> None:
    text = EDITOR.read_text(encoding="utf-8")

    text = replace_once(
        text,
        '''        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageBreakMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.backgroundColor = .secondarySystemBackground
        view.usePageViewController(false)
        view.document = document
''',
        '''        // Render one page at a time. Continuous multi-page layout can allocate
        // hundreds of MB before the first interaction on complex PDFs.
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.displaysPageBreaks = false
        view.pageBreakMargins = .zero
        view.backgroundColor = .secondarySystemBackground
        view.usePageViewController(true, withViewOptions: [
            UIPageViewController.OptionsKey.interPageSpacing: 12
        ])
        view.document = document
''',
        "single-page PDF rendering",
    )

    text = replace_once(
        text,
        '''    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
            uiView.autoScales = true
        }
        context.coordinator.model = model
        context.coordinator.attach(to: uiView)
        model.attach(pdfView: uiView)
    }
''',
        '''    func updateUIView(_ uiView: PDFView, context: Context) {
        context.coordinator.model = model
        context.coordinator.attach(to: uiView)

        // Never publish ObservableObject state from updateUIView. The old attach call
        // changed @Published properties here, creating an endless SwiftUI update loop.
        if uiView.document !== document {
            uiView.document = document
            uiView.autoScales = true
        }
    }
''',
        "remove model publishing from updateUIView",
    )

    text = replace_once(
        text,
        '''    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.detach()
    }
''',
        '''    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.detach()
        uiView.document = nil
    }
''',
        "release PDF document on dismantle",
    )

    EDITOR.write_text(text, encoding="utf-8")


def main() -> int:
    try:
        patch_model()
        patch_editor()
        print("Applied NextPDF PDFKit/SwiftUI render-loop fix")
        return 0
    except Exception as exc:
        print(f"Render-loop fix failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
