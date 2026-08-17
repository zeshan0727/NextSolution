from pathlib import Path

root = Path(__file__).resolve().parent
project = root / "project.yml"
main = root / "Sources" / "NextSolutionTransferApp.swift"
enhanced = root / "Sources" / "EnhancedUploadView.swift"

# Keep the existing target/bundle identity so 1.1.5 installs over 1.1.4.
project_text = project.read_text()
replacements = {
    'MARKETING_VERSION: 1.1.4': 'MARKETING_VERSION: 1.1.5',
    'CURRENT_PROJECT_VERSION: 114': 'CURRENT_PROJECT_VERSION: 115',
    'INFOPLIST_KEY_CFBundleDisplayName: "NextSolution Transfer"': 'INFOPLIST_KEY_CFBundleDisplayName: "NS Transfers"',
}
for old, new in replacements.items():
    if old not in project_text:
        raise SystemExit(f"project marker not found: {old}")
    project_text = project_text.replace(old, new, 1)
project.write_text(project_text)

main_text = main.read_text()
if 'UploadView().tabItem' in main_text:
    main_text = main_text.replace('UploadView().tabItem', 'EnhancedUploadView().tabItem', 1)

files_start = main_text.index('struct FilesView: View {')
files_end = main_text.index('struct TransferRow: View {')
new_files_view = r'''struct FilesView: View {
    @EnvironmentObject private var store: TransferStore
    @State private var searchText = ""
    @State private var showSearch = false

    private var filteredItems: [TransferItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.items }
        return store.items.filter { item in
            [item.name, item.fileName, item.type, item.platform, item.version, item.notes ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    VStack(spacing: 14) {
                        if store.isRefreshing { ProgressView() }
                        Image(systemName: "tray").font(.system(size: 44)).foregroundColor(.secondary)
                        Text("No Files Yet").font(.headline)
                        Text("Tap Refresh to check the NS Transfers feed.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Refresh") { Task { await store.refresh() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(30)
                } else {
                    List {
                        if showSearch {
                            Section {
                                HStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.secondary)
                                    TextField("Search files", text: $searchText)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                    if !searchText.isEmpty {
                                        Button {
                                            searchText = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Clear search")
                                    }
                                }
                            }
                        }

                        if !store.updatedAt.isEmpty {
                            Section {
                                Label("Server updated: \(store.updatedAt)", systemImage: "checkmark.icloud")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Section(header: Text(searchText.isEmpty ? "Available from NextSolution" : "Search Results")) {
                            if filteredItems.isEmpty {
                                ContentUnavailableView(
                                    "No Matching Files",
                                    systemImage: "magnifyingglass",
                                    description: Text("Try another file name, version, type, or platform.")
                                )
                            } else {
                                ForEach(filteredItems) { item in
                                    TransferRow(item: item)
                                }
                            }
                        }
                    }
                    .refreshable { await store.refresh() }
                }
            }
            .navigationTitle("NS Transfers")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation { showSearch.toggle() }
                        if !showSearch { searchText = "" }
                    } label: {
                        Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                    }
                    .accessibilityLabel(showSearch ? "Close search" : "Search files")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await store.refresh() } } label: {
                        if store.isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(store.isRefreshing)
                }
            }
            .task { await store.refresh() }
            .alert("NS Transfers", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
}

'''
main_text = main_text[:files_start] + new_files_view + main_text[files_end:]

row_start = main_text.index('struct TransferRow: View {')
row_end = main_text.index('struct DocumentPicker: UIViewControllerRepresentable {')
new_transfer_row = r'''struct TransferRow: View {
    @EnvironmentObject private var store: TransferStore
    @State private var confirmDelete = false
    let item: TransferItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: iconName).font(.title2).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.headline)
                    Text("\(item.platform) • v\(item.version)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let notes = item.notes, !notes.isEmpty {
                        Text(notes).font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            HStack {
                if store.downloadingIDs.contains(item.id) {
                    ProgressView()
                    Text("Downloading…").font(.caption)
                } else if let local = store.downloaded[item.id] {
                    ShareLink(item: local) {
                        Label("Open / Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button { Task { await store.download(item) } } label: {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                if let hash = item.sha256, !hash.isEmpty {
                    Text(String(hash.prefix(10)) + "…")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
        .confirmationDialog(
            "Delete downloaded file?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete File", role: .destructive) {
                store.remove(item)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes only the copy downloaded inside NS Transfers.")
        }
    }

    private var iconName: String {
        switch item.type.lowercased() {
        case "deb": return "shippingbox.fill"
        case "tipa", "ipa": return "apps.iphone"
        case "zip": return "archivebox.fill"
        default: return "doc.fill"
        }
    }
}

'''
main_text = main_text[:row_start] + new_transfer_row + main_text[row_end:]
main.write_text(main_text)

enhanced_text = enhanced.read_text()
old_selected_button = r'''                            Spacer()

                            Button(role: .destructive) {
                                self.selectedURL = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            Task { await uploadToGitHub(selectedURL) }
                        } label: {'''
new_selected_button = r'''                            Spacer()
                        }

                        Button(role: .destructive) {
                            self.selectedURL = nil
                            resultText = "Added file removed from NS Transfers."
                        } label: {
                            Label("Remove Added File", systemImage: "trash")
                        }
                        .disabled(isUploading)

                        Button {
                            Task { await uploadToGitHub(selectedURL) }
                        } label: {'''
if old_selected_button not in enhanced_text:
    raise SystemExit("Enhanced upload selected-file marker not found")
enhanced_text = enhanced_text.replace(old_selected_button, new_selected_button, 1)
enhanced_text = enhanced_text.replace('header: Text("Phone → NextSolution")', 'header: Text("Phone → NS Transfers")', 1)
enhanced.write_text(enhanced_text)

print("Prepared NS Transfers 1.1.5 source")
