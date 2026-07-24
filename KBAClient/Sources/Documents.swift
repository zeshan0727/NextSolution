// MARK: - Sources/Documents/DocumentPicker.swift
import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    let allowedTypes: [UTType]
    let completion: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void

        init(completion: @escaping ([URL]) -> Void) {
            self.completion = completion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls)
        }
    }
}

// MARK: - Sources/Documents/DocumentsView.swift
import SwiftUI
import UniformTypeIdentifiers

struct DocumentsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingPicker = false
    @State private var selectedCategory = DocumentCategory.other
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.documents.isEmpty {
                    VStack(spacing: 18) {
                        EmptyStateView(
                            icon: "folder.badge.plus",
                            title: "No documents",
                            message: "Import files to test the secure document area. Files stay locally on this iPhone."
                        )
                        addButton
                            .padding(.horizontal, 24)
                    }
                } else {
                    List {
                        if AppConfiguration.isLocalTestMode {
                            LocalTestBanner()
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }

                        Section {
                            Picker("Category for new files", selection: $selectedCategory) {
                                ForEach(DocumentCategory.allCases) { category in
                                    Text(category.rawValue).tag(category)
                                }
                            }
                            addButton
                        }

                        Section("Files") {
                            ForEach(store.documents) { document in
                                DocumentRow(document: document)
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            store.deleteDocument(document)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Documents")
            .sheet(isPresented: $showingPicker) {
                DocumentPicker(allowedTypes: [.pdf, .image, .plainText, .commaSeparatedText, .data]) { urls in
                    for url in urls {
                        do {
                            try store.importDocument(from: url, category: selectedCategory)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .alert("Could not import file", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var addButton: some View {
        Button {
            showingPicker = true
        } label: {
            Label("Import Documents", systemImage: "doc.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }
}

private struct DocumentRow: View {
    let document: ImportedDocument

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: document.sizeBytes, countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(BrandColor.blue)
                .frame(width: 38, height: 44)
                .background(BrandColor.paleBlue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(document.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(document.category.rawValue) • \(formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(document.addedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
