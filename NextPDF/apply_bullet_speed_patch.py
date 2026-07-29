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
    old = '''            let data = try Data(contentsOf: url)
            guard let pdf = PDFDocument(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
'''
    new = '''            // Bullet mode: let PDFKit open the local file directly. This avoids
            // copying the entire PDF into memory before the first page appears.
            guard let pdf = PDFDocument(url: url) else {
                throw CocoaError(.fileReadCorruptFile)
            }
'''
    text = replace_once(text, old, new, "PDFEditorModel direct URL open")
    MODEL.write_text(text, encoding="utf-8")


def patch_workspace() -> None:
    text = WORKSPACE.read_text(encoding="utf-8")

    old_call = '''                let localURL = try await RobustPDFFileImporter.makeVerifiedLocalCopy(of: selectedURL)
                importStatus = "Opening PDF…"
                await Task.yield()
                model.open(url: localURL)
'''
    new_call = '''                let localURL = try await RobustPDFFileImporter.prepareForImmediateOpen(selectedURL)
                importStatus = "Opening PDF…"
                await Task.yield()
                model.open(url: localURL)
'''
    text = replace_once(text, old_call, new_call, "workspace fast import call")

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

            // UIDocumentPicker is configured with asCopy=true, so the returned URL
            // is already a local app-accessible copy. Read only the tiny header.
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

private enum RobustPDFImportError:'''

    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise RuntimeError(f"workspace importer replacement: expected one match, found {count}")

    text = text.replace(
        'importStatus = "Reading selected file…"',
        'importStatus = "Opening PDF…"',
        1,
    )
    WORKSPACE.write_text(text, encoding="utf-8")


def main() -> int:
    try:
        patch_model()
        patch_workspace()
        print("Applied NextPDF bullet-speed loading patch")
        return 0
    except Exception as exc:
        print(f"Bullet-speed patch failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
