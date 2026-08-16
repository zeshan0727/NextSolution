import SwiftUI
import UniformTypeIdentifiers

private let defaultFeedURL = "https://nextsolution.app/transfer/index.json"

struct TransferFeed: Codable {
    let version: Int
    let updatedAt: String
    let files: [TransferItem]
}

struct TransferItem: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let fileName: String
    let type: String
    let platform: String
    let version: String
    let url: String
    let sha256: String?
    let notes: String?
}

@MainActor
final class TransferStore: ObservableObject {
    @Published var items: [TransferItem] = []
    @Published var isRefreshing = false
    @Published var downloadingIDs: Set<String> = []
    @Published var downloadedURLs: [String: URL] = [:]
    @Published var errorMessage: String?
    @Published var updatedAt: String = ""

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            guard var components = URLComponents(string: defaultFeedURL) else { throw URLError(.badURL) }
            components.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
            guard let url = components.url else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let feed = try JSONDecoder().decode(TransferFeed.self, from: data)
            items = feed.files
            updatedAt = feed.updatedAt
            errorMessage = nil
            refreshLocalFiles()
        } catch {
            errorMessage = "Could not load transfer feed: \(error.localizedDescription)"
        }
    }

    func refreshLocalFiles() {
        for item in items {
            let candidate = downloadsDirectory.appendingPathComponent(item.fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                downloadedURLs[item.id] = candidate
            }
        }
    }

    func download(_ item: TransferItem) async {
        guard !downloadingIDs.contains(item.id) else { return }
        downloadingIDs.insert(item.id)
        defer { downloadingIDs.remove(item.id) }
        do {
            guard let remoteURL = URL(string: item.url) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
            let destination = downloadsDirectory.appendingPathComponent(item.fileName)
            try? FileManager.default.removeItem(at: destination)
            try data.write(to: destination, options: .atomic)
            downloadedURLs[item.id] = destination
            errorMessage = nil
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    func deleteLocal(_ item: TransferItem) {
        guard let url = downloadedURLs[item.id] else { return }
        try? FileManager.default.removeItem(at: url)
        downloadedURLs.removeValue(forKey: item.id)
    }

    var downloadsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Downloads", isDirectory: true)
    }
}

@main
struct NextSolutionTransferApp: App {
    @StateObject private var store = TransferStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TransferListView()
                .tabItem { Label("Files", systemImage: "tray.and.arrow.down.fill") }
            UploadView()
                .tabItem { Label("Upload", systemImage: "arrow.up.doc.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.accentColor)
    }
}

struct TransferListView: View {
    @EnvironmentObject private var store: TransferStore

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty && store.isRefreshing {
                    ProgressView("Checking NextSolution server…")
                } else if store.items.isEmpty {
                    ContentUnavailableView {
                        Label("No Files", systemImage: "tray")
                    } description: {
                        Text("Pull to refresh the NextSolution transfer feed.")
                    }
                } else {
                    List {
                        if !store.updatedAt.isEmpty {
                            Section {
                                Label("Server updated: \(store.updatedAt)", systemImage: "checkmark.icloud")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Section("Available from NextSolution") {
                            ForEach(store.items) { item in
                                TransferRow(item: item)
                            }
                        }
                    }
                    .refreshable { await store.refresh() }
                }
            }
            .navigationTitle("NextSolution Transfer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        if store.isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(store.isRefreshing)
                }
            }
            .alert("Transfer", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .task { await store.refresh() }
        }
    }
}

struct TransferRow: View {
    @EnvironmentObject private var store: TransferStore
    let item: TransferItem

    var localURL: URL? { store.downloadedURLs[item.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.title2)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.headline)
                    Text("\(item.platform) • v\(item.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let notes = item.notes, !notes.isEmpty {
                        Text(notes).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack {
                if store.downloadingIDs.contains(item.id) {
                    ProgressView()
                    Text("Downloading…").font(.caption)
                } else if let localURL {
                    ShareLink(item: localURL) {
                        Label("Open / Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) { store.deleteLocal(item) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task { await store.download(item) }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                if let hash = item.sha256, !hash.isEmpty {
                    Text(String(hash.prefix(10)) + "…")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 5)
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

struct UploadView: View {
    @AppStorage("uploadEndpoint") private var endpoint = ""
    @AppStorage("uploadToken") private var token = ""
    @State private var showImporter = false
    @State private var selectedURL: URL?
    @State private var isUploading = false
    @State private var result = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label(selectedURL?.lastPathComponent ?? "Choose File", systemImage: "doc.badge.plus")
                    }

                    if let selectedURL {
                        Button {
                            Task { await upload(selectedURL) }
                        } label: {
                            if isUploading { ProgressView() } else { Label("Upload to Server", systemImage: "icloud.and.arrow.up") }
                        }
                        .disabled(endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUploading)
                    }
                } header: {
                    Text("Phone → Server")
                } footer: {
                    Text(endpoint.isEmpty
                         ? "Your website is currently static GitHub Pages, so uploads need a writable HTTPS endpoint. Configure it in Settings when available. No secret is embedded in this app."
                         : "The app sends the selected file as multipart/form-data to your configured HTTPS endpoint.")
                }

                if !result.isEmpty {
                    Section("Last Result") { Text(result).font(.footnote) }
                }
            }
            .navigationTitle("Upload")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .archive, .item], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): selectedURL = urls.first
                case .failure(let error): self.result = error.localizedDescription
                }
            }
        }
    }

    private func upload(_ url: URL) async {
        guard let endpointURL = URL(string: endpoint), endpointURL.scheme == "https" else {
            result = "Enter a valid HTTPS upload endpoint in Settings."
            return
        }
        isUploading = true
        defer { isUploading = false }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let boundary = "NextSolution-\(UUID().uuidString)"
            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            request.timeoutInterval = 120

            let (responseData, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: responseData, encoding: .utf8) ?? ""
            result = (200...299).contains(status) ? "Uploaded successfully. \(text)" : "Server returned HTTP \(status). \(text)"
        } catch {
            result = "Upload failed: \(error.localizedDescription)"
        }
    }
}

struct SettingsView: View {
    @AppStorage("uploadEndpoint") private var endpoint = ""
    @AppStorage("uploadToken") private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Download Feed") {
                    LabeledContent("Server", value: "nextsolution.app")
                    Text(defaultFeedURL).font(.caption.monospaced()).textSelection(.enabled)
                }
                Section("Optional Upload Backend") {
                    TextField("https://your-upload-endpoint", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("Bearer token (optional)", text: $token)
                } footer: {
                    Text("Download does not need a token. Upload credentials stay on this device and are only sent to the endpoint you configure.")
                }
                Section("Workflow") {
                    Text("New DEBs/TIPAs published by the NextSolution GitHub build pipeline appear in the Files tab after Refresh. Downloaded files are stored in this app's Documents/Downloads folder and can be shared directly to Sileo, Zebra, TrollStore, Filza or Files when those apps support the file type.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
