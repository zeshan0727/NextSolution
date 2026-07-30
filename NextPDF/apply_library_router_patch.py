#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
WORKSPACE = ROOT / "NextPDF" / "RobustPDFWorkspaceView.swift"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def main() -> int:
    try:
        text = WORKSPACE.read_text(encoding="utf-8")

        old_header = '''struct RobustPDFWorkspaceView: View {
    @StateObject private var model = PDFEditorModel()
'''
        new_header = '''struct RobustPDFWorkspaceView: View {
    @ObservedObject var router: PDFAppRouter
    @StateObject private var model = PDFEditorModel()

    init(router: PDFAppRouter) {
        self.router = router
    }
'''
        text = replace_once(text, old_header, new_header, "editor router property")

        old_alert = '''            .alert("Next PDF Pro", isPresented: $model.showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(model.alertMessage)
            }
'''
        new_alert = '''            .alert("Next PDF Pro", isPresented: $model.showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(model.alertMessage)
            }
            .onAppear {
                openRoutedPDFIfNeeded()
            }
            .onChange(of: router.openRequestID) { _ in
                openRoutedPDFIfNeeded()
            }
'''
        text = replace_once(text, old_alert, new_alert, "library open observers")

        import_marker = '''    private func importPDF(from selectedURL: URL) {'''
        router_method = '''    private func openRoutedPDFIfNeeded() {
        guard let url = router.consumePendingOpenURL() else { return }
        importPDF(from: url)
    }

'''
        if import_marker not in text:
            raise RuntimeError("import method marker not found")
        text = text.replace(import_marker, router_method + import_marker, 1)

        WORKSPACE.write_text(text, encoding="utf-8")
        print("Applied NextPDF library-to-editor routing")
        return 0
    except Exception as exc:
        print(f"Library router patch failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
