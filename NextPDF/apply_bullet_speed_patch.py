#!/usr/bin/env python3
from pathlib import Path
import re
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

    text = replace_once(text, old_method, new_method, "PDFEditorModel background install API")
    MODEL.write_text(text, encoding="utf-8")


def patch_workspace() -> None:
    text = WORKSPACE.read_text(encoding="utf-8")

    old_call = '''                let localURL = try await RobustPDFFileImporter.makeVerifiedLocalCopy(of: selectedURL)
                importStatus = "Opening PDF…"
                await Task.yield()
                model.open(url: localURL)
'''

    new_call = '''                let localURL = try await RobustPDFFileImporter.prepareForImmediateOpen(selectedURL)
                importStatus = "Opening PDF in background…"
                let loaded = try await BulletPDFBackgroundLoader.load(from: localURL, timeout: 15)
                model.install(document: loaded.document, sourceURL: localURL)
'''

    text = replace_once(text, old_call, new_call, "workspace background PDF load")

    pattern = re.compile(
        r'''private enum RobustPDFFileImporter \{.*?\n\}\n\nprivate enum RobustPDFImportError:''',
        re.DOTALL,
    )

    replacement = '''private enum RobustPDFFileImporter {
    static func prepareForImmediateOpen(_ sourceURL: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { sourceURL.stopAccessingSecurityScopedResource() }
            }

            let values = try? sourceURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                throw RobustPDFImportError.folderSelected
            }
            if let size = values?.fileSize, size <= 0 {
                throw RobustPDFImportError.emptyFile
            }

            let handle = try FileHandle(forReadingFrom: sourceURL)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 1024) ?? Data()
            guard header.range(of: Data("%PDF-".utf8)) != nil else {
                throw RobustPDFImportError.notPDF
            }

            return sourceURL
        }.value
    }
}

private final class BulletLoadedPDF: @unchecked Sendable {
    let document: PDFDocument

    init(document: PDFDocument) {
        self.document = document
    }
}

private final class BulletPDFCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func complete(_ action: () -> Void) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        action()
    }
}

private enum BulletPDFBackgroundLoader {
    static func load(from url: URL, timeout: TimeInterval) async throws -> BulletLoadedPDF {
        try await withCheckedThrowingContinuation { continuation in
            let gate = BulletPDFCompletionGate()

            DispatchQueue.global(qos: .userInitiated).async {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }

                if let pdf = PDFDocument(url: url) {
                    gate.complete {
                        continuation.resume(returning: BulletLoadedPDF(document: pdf))
                    }
                } else {
                    gate.complete {
                        continuation.resume(throwing: CocoaError(.fileReadCorruptFile))
                    }
                }
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                gate.complete {
                    continuation.resume(throwing: BulletPDFLoadError.timedOut)
                }
            }
        }
    }
}

private enum BulletPDFLoadError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        "The PDF did not open within 15 seconds. Download it fully in Files, then try again."
    }
}

private enum RobustPDFImportError:'''

    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise RuntimeError(f"workspace importer replacement: expected one match, found {count}")

    text = text.replace(
        'importStatus = "Reading selected file…"',
        'importStatus = "Preparing PDF…"',
        1,
    )
    WORKSPACE.write_text(text, encoding="utf-8")


def main() -> int:
    try:
        patch_model()
        patch_workspace()
        print("Applied NextPDF background PDF loader with timeout")
        return 0
    except Exception as exc:
        print(f"Background-loader patch failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
