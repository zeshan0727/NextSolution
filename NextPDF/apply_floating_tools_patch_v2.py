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

        old_layout = '''    private func editorLayout(document: PDFDocument) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if sidebarVisible {
                    RobustEditorSidebar(
                        model: model,
                        onEditText: openExistingTextEditor,
                        onAddText: { showingAddText = true },
                        onDate: openDateEditor,
                        onSignature: { showingSignature = true },
                        onDraw: { showingDrawing = true },
                        onPages: { showingPages = true },
                        onSearch: { showingSearch = true },
                        onSave: { model.saveInsideApp(kind: .editable) },
                        onSecureSave: { model.saveInsideApp(kind: .secureRasterized) },
                        onExport: { kind in
                            exportKind = kind
                            showingExporter = true
                        },
                        onShare: share
                    )
                    .frame(width: sidebarWidth(for: geometry.size.width))
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    Divider()
                }

                PDFKitEditorView(document: document, model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))
            }
            .animation(.easeInOut(duration: 0.2), value: sidebarVisible)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editorStatusBar
                .background(.ultraThinMaterial)
        }
    }

    private func sidebarWidth(for totalWidth: CGFloat) -> CGFloat {
        if totalWidth >= 900 { return 225 }
        if totalWidth >= 650 { return 190 }
        return min(148, max(132, totalWidth * 0.35))
    }
'''

        new_layout = '''    private func editorLayout(document: PDFDocument) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                PDFKitEditorView(document: document, model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))

                if sidebarVisible {
                    RobustEditorSidebar(
                        model: model,
                        onCollapse: hideFloatingTools,
                        onEditText: openExistingTextEditor,
                        onAddText: { showingAddText = true },
                        onDate: openDateEditor,
                        onSignature: { showingSignature = true },
                        onDraw: { showingDrawing = true },
                        onPages: { showingPages = true },
                        onSearch: { showingSearch = true },
                        onSave: { model.saveInsideApp(kind: .editable) },
                        onSecureSave: { model.saveInsideApp(kind: .secureRasterized) },
                        onExport: { kind in
                            exportKind = kind
                            showingExporter = true
                        },
                        onShare: share
                    )
                    .frame(
                        width: floatingToolsWidth(for: geometry.size.width),
                        maxHeight: max(240, geometry.size.height - 24)
                    )
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 0.75)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
                    .padding(.leading, 10)
                    .padding(.vertical, 12)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    collapsedToolsHandle
                        .padding(.leading, 5)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.86), value: sidebarVisible)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editorStatusBar
                .background(.ultraThinMaterial)
        }
    }

    private func floatingToolsWidth(for totalWidth: CGFloat) -> CGFloat {
        if totalWidth >= 900 { return 270 }
        if totalWidth >= 650 { return 245 }
        return min(255, max(218, totalWidth * 0.68))
    }

    private var collapsedToolsHandle: some View {
        Button(action: showFloatingTools) {
            VStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show editing tools")
        .accessibilityHint("Opens the floating PDF editing palette")
    }

    private func hideFloatingTools() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        sidebarVisible = false
    }

    private func showFloatingTools() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        sidebarVisible = true
    }
'''
        text = replace_once(text, old_layout, new_layout, "floating editor layout")

        text = replace_once(
            text,
            '''                Button {
                    sidebarVisible.toggle()
                } label: {
                    Label(sidebarVisible ? "Hide Tools" : "Show Tools", systemImage: "sidebar.left")
                }
''',
            '''                Button {
                    sidebarVisible ? hideFloatingTools() : showFloatingTools()
                } label: {
                    Label(
                        sidebarVisible ? "Hide Tools" : "Show Tools",
                        systemImage: sidebarVisible ? "chevron.left.circle" : "slider.horizontal.3"
                    )
                }
''',
            "toolbar tools toggle",
        )

        text = replace_once(
            text,
            '''            } else if model.hasSelectedAnnotation {
                Label(model.selectedAnnotationName, systemImage: "selection.pin.in.out")
                    .foregroundStyle(.blue)
                    .font(.caption.weight(.semibold))
            } else {
''',
            '''            } else if model.hasSelectedAnnotation {
                Label("\\(model.selectedAnnotationName) • drag to move • pinch to resize", systemImage: "selection.pin.in.out")
                    .foregroundStyle(.blue)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
''',
            "selected annotation guidance",
        )

        text = replace_once(
            text,
            '''private struct RobustEditorSidebar: View {
    @ObservedObject var model: PDFEditorModel
    let onEditText: () -> Void
''',
            '''private struct RobustEditorSidebar: View {
    @ObservedObject var model: PDFEditorModel
    let onCollapse: () -> Void
    let onEditText: () -> Void
''',
            "sidebar collapse property",
        )

        text = replace_once(
            text,
            '''                VStack(alignment: .leading, spacing: 5) {
                    Label("Edit Tools", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Text(model.hasTextSelection ? "Selected text is ready" : "Select text or choose a tool")
                        .font(.caption2)
                        .foregroundStyle(model.hasTextSelection ? .blue : .secondary)
                }
''',
            '''                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Edit Tools", systemImage: "slider.horizontal.3")
                            .font(.headline)
                        Text(model.hasTextSelection ? "Selected text is ready" : "Select text or choose a tool")
                            .font(.caption2)
                            .foregroundStyle(model.hasTextSelection ? .blue : .secondary)
                    }

                    Spacer(minLength: 4)

                    Button(action: onCollapse) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Color.secondary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide editing tools")
                }
''',
            "palette collapse button",
        )

        text = replace_once(
            text,
            '''                RobustSidebarSection(title: "TEXT") {
                    RobustSidebarButton("Edit Text", icon: "character.cursor.ibeam", primary: true, action: onEditText)
                    RobustSidebarButton("Add Text", icon: "text.badge.plus", action: onAddText)
                    RobustSidebarButton("Change Date", icon: "calendar", action: onDate)
                    RobustSidebarButton("Remove Text", icon: "eraser") { model.removeSelectedText() }
                        .opacity(model.hasTextSelection ? 1 : 0.55)
                }

                RobustSidebarSection(title: "MARKUP") {
                    RobustSidebarButton("Highlight", icon: "highlighter") { model.markSelection(.highlight) }
                    RobustSidebarButton("Underline", icon: "underline") { model.markSelection(.underline) }
                    RobustSidebarButton("Strike Out", icon: "strikethrough") { model.markSelection(.strikeOut) }
                    RobustSidebarButton("Whiteout", icon: "rectangle.fill") { model.redactSelection(coverColor: .white) }
                    RobustSidebarButton("Redact", icon: "eye.slash.fill") { model.redactSelection(coverColor: .black) }
                }
''',
            '''                RobustSidebarSection(title: "TEXT") {
                    RobustSidebarButton("Edit Text", icon: "character.cursor.ibeam", primary: true, action: onEditText)
                        .disabled(!model.hasTextSelection)
                    RobustSidebarButton("Add Text", icon: "text.badge.plus", action: onAddText)
                    RobustSidebarButton("Change Date", icon: "calendar", action: onDate)
                        .disabled(!model.hasTextSelection)
                    RobustSidebarButton("Remove Text", icon: "eraser") { model.removeSelectedText() }
                        .disabled(!model.hasTextSelection)
                }

                RobustSidebarSection(title: "MARKUP") {
                    RobustSidebarButton("Highlight", icon: "highlighter") { model.markSelection(.highlight) }
                        .disabled(!model.hasTextSelection)
                    RobustSidebarButton("Underline", icon: "underline") { model.markSelection(.underline) }
                        .disabled(!model.hasTextSelection)
                    RobustSidebarButton("Strike Out", icon: "strikethrough") { model.markSelection(.strikeOut) }
                        .disabled(!model.hasTextSelection)
                    RobustSidebarButton("Whiteout", icon: "rectangle.fill") { model.redactSelection(coverColor: .white) }
                        .disabled(!model.hasTextSelection)
                    RobustSidebarButton("Redact", icon: "eye.slash.fill") { model.redactSelection(coverColor: .black) }
                        .disabled(!model.hasTextSelection)
                }
''',
            "disable unavailable selection tools",
        )

        sidebar_start = text.find("private struct RobustEditorSidebar: View {")
        sidebar_end = text.find("private struct RobustSidebarSection", sidebar_start)
        if sidebar_start == -1 or sidebar_end == -1:
            raise RuntimeError("could not isolate floating sidebar source")
        before = text[:sidebar_start]
        sidebar = text[sidebar_start:sidebar_end]
        after = text[sidebar_end:]
        sidebar = replace_once(
            sidebar,
            '''        .background(.ultraThinMaterial)
''',
            '''        .background(Color.clear)
''',
            "floating sidebar clear background",
        )
        text = before + sidebar + after

        WORKSPACE.write_text(text, encoding="utf-8")
        print("Applied robust floating collapsible editing palette")
        return 0
    except Exception as exc:
        print(f"Floating tools V2 patch failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
