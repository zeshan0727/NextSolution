import SwiftUI
import UniformTypeIdentifiers

private let feedURLString = "https://nextsolution.app/transfer/index.json"

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
    @Published var updatedAt = ""
    @Published var isRefreshing = false
    @Published var downloadingIDs: Set<String> = []
    @Published var downloaded: [String: URL] = [:]
    @Published var errorMessage: String?

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
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let feed = try JSONDecoder().decode(TransferFeed.self, from: data)
            items = feed.files
            updatedAt = feed.updatedAt
            for item in items {
                let file = downloadsDirectory.appendingPathComponent(item.fileName)
                if FileManager.default.fileExists(atPath: file.path) { downloaded[item.id] = file }
            }
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
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
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

    func remove(_ item: TransferItem) {
        if let url = downloaded[item.id] { try? FileManager.default.removeItem(at: url) }
        downloaded.removeValue(forKey: item.id)
    }
}

@main
struct NextSolutionTransferApp: App {
    @StateObject private var store = TransferStore()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(store) }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            FilesView().tabItem { Label("Files", systemImage: "tray.and.arrow.down.fill") }
            UploadView().tabItem { Label("Upload", systemImage: "arrow.up.doc.fill") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

struct FilesView: View {
    @EnvironmentObject private var store: TransferStore

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    VStack(spacing: 14) {
                        if store.isRefreshing { ProgressView() }
                        Image(systemName: "tray").font(.system(size: 44)).foregroundColor(.secondary)
                        Text("No Files Yet").font(.headline)
                        Text("Tap Refresh to check your NextSolution transfer feed.")
                            .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Button("Refresh") { Task { await store.refresh() } }.buttonStyle(.borderedProminent)
                    }
                    .padding(30)
                } else {
                    List {
                        if !store.updatedAt.isEmpty {
                            Section {
                                Label("Server updated: \(store.updatedAt)", systemImage: "checkmark.icloud")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Section(header: Text("Available from NextSolution")) {
                            ForEach(store.items) { item in TransferRow(item: item) }
                        }
                    }
                    .refreshable { await store.refresh() }
                }
            }
            .navigationTitle("NextSolution Transfer")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await store.refresh() } } label: {
                        if store.isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(store.isRefreshing)
                }
            }
            .task { await store.refresh() }
            .alert("Transfer", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
    }
}

struct TransferRow: View {
    @EnvironmentObject private var store: TransferStore
    let item: TransferItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: iconName).font(.title2).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.headline)
                    Text("\(item.platform) • v\(item.version)").font(.subheadline).foregroundColor(.secondary)
                    if let notes = item.notes, !notes.isEmpty { Text(notes).font(.caption).foregroundColor(.secondary) }
                }
            }
            HStack {
                if store.downloadingIDs.contains(item.id) {
                    ProgressView(); Text("Downloading…").font(.caption)
                } else if let local = store.downloaded[item.id] {
                    ShareLink(item: local) { Label("Open / Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.borderedProminent)
                    Button(role: .destructive) { store.remove(item) } label: { Image(systemName: "trash") }
                        .buttonStyle(.bordered)
                } else {
                    Button { Task { await store.download(item) } } label: { Label("Download", systemImage: "arrow.down.circle.fill") }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                if let hash = item.sha256, !hash.isEmpty {
                    Text(String(hash.prefix(10)) + "…").font(.caption2.monospaced()).foregroundColor(.secondary)
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
    @State private var importing = false
    @State private var selectedURL: URL?
    @State private var isUploading = false
    @State private var resultText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Phone → Server"), footer: Text(uploadFooter)) {
                    Button { importing = true } label: { Label(selectedURL?.lastPathComponent ?? "Choose File", systemImage: "doc.badge.plus") }
                    if let selectedURL {
                        Button { Task { await upload(selectedURL) } } label: {
                            if isUploading { ProgressView() } else { Label("Upload to Server", systemImage: "icloud.and.arrow.up") }
                        }
                        .disabled(endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUploading)
                    }
                }
                if !resultText.isEmpty {
                    Section(header: Text("Last Result")) { Text(resultText).font(.footnote) }
                }
            }
            .navigationTitle("Upload")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .archive, .item], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): selectedURL = urls.first
                case .failure(let error): resultText = error.localizedDescription
                }
            }
        }
    }

    private var uploadFooter: String {
        endpoint.isEmpty
            ? "Downloads work immediately. Your current GitHub Pages website is read-only, so phone uploads need a writable HTTPS endpoint configured in Settings. No secret is embedded in this TIPA."
            : "Uploads the selected file as multipart/form-data to your configured HTTPS endpoint."
    }

    private func upload(_ url: URL) async {
        guard let endpointURL = URL(string: endpoint), endpointURL.scheme == "https" else {
            resultText = "Enter a valid HTTPS upload endpoint in Settings."
            return
        }
        isUploading = true
        defer { isUploading = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let fileData = try Data(contentsOf: url)
            let boundary = "NextSolution-\(UUID().uuidString)"
            var body = Data()
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".utf8))
            body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
            body.append(fileData)
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.httpBody = body
            request.timeoutInterval = 120
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data, encoding: .utf8) ?? ""
            resultText = (200...299).contains(status) ? "Uploaded successfully. \(text)" : "Server returned HTTP \(status). \(text)"
        } catch {
            resultText = "Upload failed: \(error.localizedDescription)"
        }
    }
}

struct SettingsView: View {
    @AppStorage("uploadEndpoint") private var endpoint = ""
    @AppStorage("uploadToken") private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Download Feed")) {
                    HStack { Text("Server"); Spacer(); Text("nextsolution.app").foregroundColor(.secondary) }
                    Text(feedURLString).font(.caption.monospaced()).textSelection(.enabled)
                }
                Section(header: Text("Optional Upload Backend"), footer: Text("Download needs no token. Upload credentials stay on this device and are only sent to the HTTPS endpoint you configure.")) {
                    TextField("https://your-upload-endpoint", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("Bearer token (optional)", text: $token)
                }
                Section(header: Text("Workflow")) {
                    Text("New DEBs or TIPAs published by the NextSolution GitHub build pipeline appear in Files after Refresh. Downloaded files are saved under this app's Documents/Downloads folder and can be shared to Sileo, Zebra, TrollStore, Filza or Files when those apps support the file type.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
