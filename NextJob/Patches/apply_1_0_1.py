from pathlib import Path
import re

path = Path("NextJob/Views/JobDetailView.swift")
source = path.read_text(encoding="utf-8")

if "@State private var pickerMode: DocumentPickerMode" in source:
    raise SystemExit(0)

source = source.replace(
    "    @State private var pickerKind: AttachmentKind = .related\n",
    "    @State private var pickerKind: AttachmentKind = .related\n"
    "    @State private var pickerMode: DocumentPickerMode = .files\n"
    "    @State private var isImportingItems = false\n"
    "    @State private var importMessage = \"Adding selected items…\"\n",
    1,
)

root_end = """            } else {
                EmptyStateView(title: "Job not found", message: "This job may have been deleted.", systemImage: "exclamationmark.triangle")
                    .padding()
            }
        }
        .navigationTitle"""
root_replacement = """            } else {
                EmptyStateView(title: "Job not found", message: "This job may have been deleted.", systemImage: "exclamationmark.triangle")
                    .padding()
            }

            if isImportingItems {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(importMessage)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(32)
            }
        }
        .navigationTitle"""
if root_end not in source:
    raise RuntimeError("Could not locate the JobDetail root view")
source = source.replace(root_end, root_replacement, 1)

picker_pattern = re.compile(
    r"        \.sheet\(isPresented: \$showingPicker\) \{\n"
    r"            DocumentPicker\(allowsMultipleSelection: true\) \{ result in\n"
    r"                showingPicker = false\n"
    r"                handleFiles\(result\)\n"
    r"            \}\n"
    r"        \}\n"
)
picker_replacement = """        .sheet(isPresented: $showingPicker) {
            DocumentPicker(
                mode: pickerMode,
                allowsMultipleSelection: pickerMode == .files
            ) { result in
                showingPicker = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    handleSelectedItems(result)
                }
            }
        }
"""
source, count = picker_pattern.subn(picker_replacement, source, count=1)
if count != 1:
    raise RuntimeError("Could not update the document picker sheet")

files_function_pattern = re.compile(
    r"    private func filesCard\(_ job: JobRecord, kind: AttachmentKind\) -> some View \{.*?"
    r"\n    private func emailPanel",
    re.DOTALL,
)
files_function = """    private func filesCard(_ job: JobRecord, kind: AttachmentKind) -> some View {
        let files = job.attachments.filter { $0.kind == kind }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: kind.title, systemImage: kind == .related ? "paperclip" : "checkmark.doc")
                Menu {
                    Button {
                        beginPicking(.files, kind: kind)
                    } label: {
                        Label("Add Files", systemImage: "doc.badge.plus")
                    }
                    Button {
                        beginPicking(.folder, kind: kind)
                    } label: {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .disabled(isImportingItems)
            }
            if files.isEmpty {
                Text(kind == .related ? "Add source files, folders, spreadsheets or instructions." : "Upload completed files or a complete work folder to send back.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(files) { attachment in
                    let isFolder = JobFileService.shared.isFolder(attachment, jobID: job.id)
                    HStack(spacing: 12) {
                        Image(systemName: isFolder ? "folder.fill" : "doc.fill")
                            .foregroundStyle(isFolder ? .orange : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.originalName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(JobFileService.shared.detailText(for: attachment, jobID: job.id))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            if !isFolder {
                                Button {
                                    previewItem = PreviewItem(url: JobFileService.shared.url(for: attachment, jobID: job.id))
                                } label: {
                                    Label("Preview", systemImage: "eye")
                                }
                            }
                            Button {
                                let url = JobFileService.shared.url(for: attachment, jobID: job.id)
                                sharePayload = SharePayload(items: [url])
                            } label: {
                                Label(isFolder ? "Share Folder" : "Share", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                store.removeAttachment(attachment, from: job.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .glassCard()
    }

    private func emailPanel"""
source, count = files_function_pattern.subn(files_function, source, count=1)
if count != 1:
    raise RuntimeError("Could not replace the attachments section")

handler_pattern = re.compile(
    r"    private func handleFiles\(_ result: Result<\[URL\], Error>\) \{.*?"
    r"\n    private func requestDocuments",
    re.DOTALL,
)
handler = '''    private func beginPicking(_ mode: DocumentPickerMode, kind: AttachmentKind) {
        guard !isImportingItems else { return }
        pickerKind = kind
        pickerMode = mode
        showingPicker = true
    }

    private func handleSelectedItems(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }

            let selectedKind = pickerKind
            if pickerMode == .folder {
                importMessage = "Adding folder and its contents…"
            } else {
                importMessage = "Adding \\(urls.count) selected file\\(urls.count == 1 ? \"\" : \"s\")…"
            }
            isImportingItems = true

            DispatchQueue.global(qos: .userInitiated).async {
                let importResult = Result {
                    try JobFileService.shared.copyItems(urls, jobID: jobID, kind: selectedKind)
                }
                DispatchQueue.main.async {
                    isImportingItems = false
                    switch importResult {
                    case .success(let attachments):
                        store.addAttachments(attachments, to: jobID)
                    case .failure(let error):
                        showNotice("Items Not Added", error.localizedDescription)
                    }
                }
            }
        } catch {
            showNotice("Items Not Added", error.localizedDescription)
        }
    }

    private func requestDocuments'''
source, count = handler_pattern.subn(lambda _: handler, source, count=1)
if count != 1:
    raise RuntimeError("Could not replace the file import handler")

path.write_text(source, encoding="utf-8")
