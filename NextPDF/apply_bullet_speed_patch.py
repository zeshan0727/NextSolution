#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
MODEL = ROOT / "NextPDF" / "PDFEditorModel.swift"
WORKSPACE = ROOT / "NextPDF" / "RobustPDFWorkspaceView.swift"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def patch_model() -> None:
    text = MODEL.read_text(encoding="utf-8")

    old_method = '''    func open(url: URL) {
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
'''

    new_method = '''    func open(url: URL) {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            guard let pdf = PDFDocument(url: url) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            install(document: pdf, sourceURL: url)
        } catch {
            present(error: error)
        }
    }

    func install(document pdf: PDFDocument, sourceURL url: URL) {
        self.sourceURL = url
        documentTitle = url.deletingPathExtension().lastPathComponent
        document = pdf
        pdfView?.document = pdf
        selectedAnnotation = nil
        selectedAnnotationPage = nil
        undoStack.removeAll()
        redoStack.removeAll()
        refreshUndoState()
        refreshDocumentState()
    }
'''

    text = replace_once(text, old_method, new_method, "PDFEditorModel install API")
    MODEL.write_text(text, encoding="utf-8")


def patch_workspace() -> None:
    text = WORKSPACE.read_text(encoding="utf-8")

    old_state = '''    @State private var shareItem: RobustShareItem?
    @State private var exportKind: PDFExportKind = .editable
'''
    new_state = '''    @State private var shareItem: RobustShareItem?
    @State private var exportKind: PDFExportKind = .editable
    @State private var importRequestID = UUID()
'''
    text = replace_once(text, old_state, new_state, "import request state")

    old_overlay = '''    private var loadingOverlay: some View {
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
'''

    new_overlay = '''    private var loadingOverlay: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                VStack(alignment: .leading, spacing: 2) {
                    Text(importStatus)
                        .font(.headline)
                    Text("You can cancel immediately if this Files provider is not responding.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }

            Button(role: .cancel) {
                cancelCurrentImport()
            } label: {
                Label("Cancel Loading", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 12)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
'''
    text = replace_once(text, old_overlay, new_overlay, "non-blocking loading banner")

    old_import = '''    private func importPDF(from selectedURL: URL) {
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
'''

    new_import = '''    private func importPDF(from selectedURL: URL) {
        guard !isImporting else { return }

        let requestID = UUID()
        importRequestID = requestID
        isImporting = true
        importStatus = "Opening PDF…"

        Task {
            do {
                // No header read, no duplicate copy and no synchronous file validation.
                // The document picker already supplies an app-accessible local copy.
                let loaded = try await NoStuckPDFLoader.load(from: selectedURL, timeout: 6)
                guard importRequestID == requestID else { return }

                // Hide the loading UI before PDFKit receives the document. Even if
                // first-page rendering is expensive, the user is never trapped behind it.
                isImporting = false
                await Task.yield()
                guard importRequestID == requestID else { return }

                model.install(document: loaded.document, sourceURL: selectedURL)
                sidebarVisible = true
            } catch {
                guard importRequestID == requestID else { return }
                isImporting = false
                model.present(error: error)
            }
        }
    }

    private func cancelCurrentImport() {
        importRequestID = UUID()
        isImporting = false
        importStatus = "Opening PDF…"
    }
'''
    text = replace_once(text, old_import, new_import, "cancel-safe PDF import")

    loader_code = '''

private final class NoStuckLoadedPDF: @unchecked Sendable {
    let document: PDFDocument

    init(document: PDFDocument) {
        self.document = document
    }
}

private final class NoStuckCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func finish(_ action: () -> Void) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        action()
    }
}

private enum NoStuckPDFLoader {
    static func load(from url: URL, timeout: TimeInterval) async throws -> NoStuckLoadedPDF {
        try await withCheckedThrowingContinuation { continuation in
            let gate = NoStuckCompletionGate()

            // This is intentionally unstructured. The timeout is allowed to return
            // immediately without waiting for a blocked third-party Files provider.
            DispatchQueue.global(qos: .userInitiated).async {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }

                if let pdf = PDFDocument(url: url) {
                    gate.finish {
                        continuation.resume(returning: NoStuckLoadedPDF(document: pdf))
                    }
                } else {
                    gate.finish {
                        continuation.resume(throwing: NoStuckPDFLoadError.cannotOpen)
                    }
                }
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                gate.finish {
                    continuation.resume(throwing: NoStuckPDFLoadError.timedOut)
                }
            }
        }
    }
}

private enum NoStuckPDFLoadError: LocalizedError {
    case timedOut
    case cannotOpen

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "This Files provider did not supply the PDF within 6 seconds. Open the PDF once in Files so it downloads locally, then select it again."
        case .cannotOpen:
            return "The selected file could not be opened as a PDF. It may be damaged or password-protected."
        }
    }
}
'''

    marker = '''private enum RobustPDFImportError: LocalizedError {'''
    if marker not in text:
        raise RuntimeError("loader insertion marker not found")
    text = text.replace(marker, loader_code + "\n\n" + marker, 1)

    WORKSPACE.write_text(text, encoding="utf-8")


def main() -> int:
    try:
        patch_model()
        patch_workspace()
        print("Applied NextPDF non-blocking cancel-safe loader")
        return 0
    except Exception as exc:
        print(f"No-stuck loader patch failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
