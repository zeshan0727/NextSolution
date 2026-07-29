import SwiftUI
import UIKit
import PDFKit

struct PDFKitEditorView: UIViewRepresentable {
    let document: PDFDocument
    @ObservedObject var model: PDFEditorModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.minScaleFactor = 0.45
        view.maxScaleFactor = 5.0
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageBreakMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.backgroundColor = .secondarySystemBackground
        view.usePageViewController(false)
        view.document = document

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleAnnotationPan(_:)))
        pan.cancelsTouchesInView = false
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        context.coordinator.attach(to: view)
        model.attach(pdfView: view)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
            uiView.autoScales = true
        }
        context.coordinator.model = model
        context.coordinator.attach(to: uiView)
        model.attach(pdfView: uiView)
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var model: PDFEditorModel
        private weak var pdfView: PDFView?
        private var observingView: PDFView?

        init(model: PDFEditorModel) {
            self.model = model
        }

        func attach(to view: PDFView) {
            guard observingView !== view else { return }
            detach()
            pdfView = view
            observingView = view
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(selectionChanged),
                name: Notification.Name.PDFViewSelectionChanged,
                object: view
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged),
                name: Notification.Name.PDFViewPageChanged,
                object: view
            )
        }

        func detach() {
            if let observingView {
                NotificationCenter.default.removeObserver(self, name: Notification.Name.PDFViewSelectionChanged, object: observingView)
                NotificationCenter.default.removeObserver(self, name: Notification.Name.PDFViewPageChanged, object: observingView)
            }
            observingView = nil
            pdfView = nil
        }

        @objc func selectionChanged() {
            Task { @MainActor in
                model.selectionDidChange()
            }
        }

        @objc func pageChanged() {
            Task { @MainActor in
                model.pageDidChange()
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = pdfView else { return }
            let point = recognizer.location(in: view)
            Task { @MainActor in
                model.handleTap(at: point, in: view)
            }
        }

        @objc func handleAnnotationPan(_ recognizer: UIPanGestureRecognizer) {
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
    }
}
