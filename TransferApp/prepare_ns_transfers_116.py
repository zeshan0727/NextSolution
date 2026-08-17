from pathlib import Path

root = Path(__file__).resolve().parent
project = root / "project.yml"
main = root / "Sources" / "NextSolutionTransferApp.swift"
enhanced = root / "Sources" / "EnhancedUploadView.swift"

# Preserve bundle/product identity while moving the corrected test build to 1.1.6.
project_text = project.read_text()
replacements = {
    'MARKETING_VERSION: 1.1.4': 'MARKETING_VERSION: 1.1.6',
    'CURRENT_PROJECT_VERSION: 114': 'CURRENT_PROJECT_VERSION: 116',
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

store_start = main_text.index('@MainActor\nfinal class TransferStore: ObservableObject {')
store_end = main_text.index('\n@main\nstruct NextSolutionTransferApp: App {')
new_store = r'''@MainActor
final class TransferStore: ObservableObject {
    @Published var items: [TransferItem] = []
    @Published var updatedAt = ""
    @Published var isRefreshing = false
    @Published var downloadingIDs: Set<String> = []
    @Published var deletingRootIDs: Set<String> = []
    @Published var downloaded: [String: URL] = [:]
    @Published var errorMessage: String?

    private struct GitHubContent: Decodable {
        let sha: String
        let content: String?
    }

    var downloadsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            guard var components = URLComponents(string: feedURLString) else { throw URLError(.badURL) }
            components.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
            guard let url = components.url else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let feed = try JSONDecoder().decode(TransferFeed.self, from: data)
            items = feed.files
            updatedAt = feed.updatedAt

            try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
            var rebuilt: [String: URL] = [:]
            for item in items {
                let local = downloadsDirectory.appendingPathComponent(item.fileName)
                if FileManager.default.fileExists(atPath: local.path) {
                    rebuilt[item.id] = local
                }
            }
            downloaded = rebuilt
            errorMessage = nil
        } catch {
            errorMessage = "Could not load server feed: \(error.localizedDescription)"
        }
    }

    func download(_ item: TransferItem) async {
        guard !downloadingIDs.contains(item.id) else { return }
        downloadingIDs.insert(item.id)
        defer { downloadingIDs.remove(item.id) }
        do {
            guard let remote = URL(string: item.url) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: remote)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
            let local = downloadsDirectory.appendingPathComponent(item.fileName)
            try? FileManager.default.removeItem(at: local)
            try data.write(to: local, options: .atomic)
            downloaded[item.id] = local
            errorMessage = nil
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    // Local-device delete remains independent from root/server deletion.
    func removeDeviceCopy(_ item: TransferItem) {
        if let url = downloaded[item.id] {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                errorMessage = "Could not delete the device copy: \(error.localizedDescription)"
                return
            }
        }
        downloaded.removeValue(forKey: item.id)
        errorMessage = nil
    }

    // Swipe-delete removes the root file and then removes its entry from transfer/index.json.
    // It intentionally does not touch an already-downloaded device copy.
    func deleteFromRoot(_ item: TransferItem) async {
        guard !deletingRootIDs.contains(item.id) else { return }
        let token = SecureTokenStore.load().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "GitHub token is not configured. Add a token with Contents: Read and write in Settings."
            return
        }

        deletingRootIDs.insert(item.id)
        defer { deletingRootIDs.remove(item.id) }

        do {
            let rootPath = try rootRepositoryPath(for: item)

            // Read both current objects before committing either change.
            let rootContent = try await fetchGitHubContent(path: rootPath, token: token)
            let indexContent = try await fetchGitHubContent(path: "transfer/index.json", token: token)
            guard let encodedFeed = indexContent.content,
                  let feedData = Data(base64Encoded: encodedFeed, options: .ignoreUnknownCharacters) else {
                throw rootError("Could not read the root transfer index from GitHub.")
            }

            let currentFeed = try JSONDecoder().decode(TransferFeed.self, from: feedData)
            guard currentFeed.files.contains(where: { $0.id == item.id }) else {
                throw rootError("This item is no longer present in the root transfer index. Refresh the list and try again.")
            }

            try await deleteGitHubFile(path: rootPath, sha: rootContent.sha, token: token)

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let revisedFeed = TransferFeed(
                version: currentFeed.version,
                updatedAt: timestamp,
                files: currentFeed.files.filter { $0.id != item.id }
            )
            try await updateRootFeed(revisedFeed, sha: indexContent.sha, token: token)

            items.removeAll { $0.id == item.id }
            updatedAt = timestamp
            errorMessage = nil
        } catch {
            errorMessage = "Root delete failed: \(error.localizedDescription)"
        }
    }

    private func rootRepositoryPath(for item: TransferItem) throws -> String {
        guard let url = URL(string: item.url),
              url.host?.lowercased() == "nextsolution.cc" else {
            throw rootError("For safety, root delete only supports files hosted on nextsolution.cc.")
        }
        let decodedPath = url.path.removingPercentEncoding ?? url.path
        guard decodedPath.hasPrefix("/transfer/files/") else {
            throw rootError("For safety, this item is outside the deletable transfer/files root.")
        }
        return String(decodedPath.dropFirst())
    }

    private func fetchGitHubContent(path: String, token: String) async throws -> GitHubContent {
        var components = URLComponents(string: githubContentsURL(path: path))
        components?.queryItems = [URLQueryItem(name: "ref", value: "main")]
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = githubRequest(url: url, token: token, method: "GET")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateGitHubResponse(data: data, response: response)
        return try JSONDecoder().decode(GitHubContent.self, from: data)
    }

    private func deleteGitHubFile(path: String, sha: String, token: String) async throws {
        guard let url = URL(string: githubContentsURL(path: path)) else { throw URLError(.badURL) }
        let body: [String: Any] = [
            "message": "Delete \(path) from NS Transfers",
            "sha": sha,
            "branch": "main"
        ]
        var request = githubRequest(url: url, token: token, method: "DELETE")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateGitHubResponse(data: data, response: response)
    }

    private func updateRootFeed(_ feed: TransferFeed, sha: String, token: String) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        var feedData = try encoder.encode(feed)
        feedData.append(0x0A)

        guard let url = URL(string: githubContentsURL(path: "transfer/index.json")) else { throw URLError(.badURL) }
        let body: [String: Any] = [
            "message": "Remove root transfer item from NS Transfers",
            "content": feedData.base64EncodedString(),
            "sha": sha,
            "branch": "main"
        ]
        var request = githubRequest(url: url, token: token, method: "PUT")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateGitHubResponse(data: data, response: response)
    }

    private func githubContentsURL(path: String) -> String {
        let encoded = path.split(separator: "/").map { component -> String in
            let value = String(component)
            return value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
        }.joined(separator: "/")
        return "https://api.github.com/repos/\(githubRepo)/contents/\(encoded)"
    }

    private func githubRequest(url: URL, token: String, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("NS-Transfers", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validateGitHubResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = json?["message"] as? String ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw rootError("GitHub HTTP \(http.statusCode): \(message)")
        }
    }

    private func rootError(_ message: String) -> NSError {
        NSError(domain: "NS-Transfers.RootDelete", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
'''
main_text = main_text[:store_start] + new_store + main_text[store_end:]

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
                                VStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                    Text("No Matching Files").font(.headline)
                                    Text("Try another file name, version, type, or platform.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
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
    @State private var confirmRootDelete = false
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
                if store.deletingRootIDs.contains(item.id) {
                    ProgressView()
                    Text("Deleting from root…").font(.caption)
                } else if store.downloadingIDs.contains(item.id) {
                    ProgressView()
                    Text("Downloading…").font(.caption)
                } else if let local = store.downloaded[item.id] {
                    ShareLink(item: local) {
                        Label("Open / Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)

                    // Device-only delete stays as the original separate trash button.
                    Button(role: .destructive) {
                        store.removeDeviceCopy(item)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Delete from Device")
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                confirmRootDelete = true
            } label: {
                Label("Delete Root", systemImage: "trash.slash")
            }
            .disabled(store.deletingRootIDs.contains(item.id))
        }
        .confirmationDialog(
            "Delete from root server?",
            isPresented: $confirmRootDelete,
            titleVisibility: .visible
        ) {
            Button("Delete from Root", role: .destructive) {
                Task { await store.deleteFromRoot(item) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the root/server file and its NS Transfers feed entry. A copy already downloaded to this device is not deleted.")
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
enhanced_text = enhanced_text.replace('Upload \\(safeName) from NextSolution Transfer', 'Upload \\(safeName) from NS Transfers', 1)
enhanced_text = enhanced_text.replace('NextSolution-Transfer', 'NS-Transfers')
enhanced.write_text(enhanced_text)

print("Prepared NS Transfers 1.1.6 with root swipe delete")
