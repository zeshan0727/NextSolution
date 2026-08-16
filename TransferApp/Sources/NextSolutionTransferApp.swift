import SwiftUI
import UniformTypeIdentifiers
import Security

private let feedURLString = "https://nextsolution.app/transfer/index.json"
private let githubRepo = "zeshan0727/NextSolution"

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

enum SecureTokenStore {
    private static let service = "com.nextsolution.transfer"
    private static let account = "github-upload-token"

    static func save(_ token: String) {
        delete()
        guard !token.isEmpty, let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return "" }
        return token
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
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
    @State private var importing = false
    @State private var selectedURL: URL?
    @State private var isUploading = false
    @State private var resultText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Phone → NextSolution Server"), footer: Text("Files are uploaded to transfer/uploads/ in your NextSolution GitHub repo. The token is read from iOS Keychain and never bundled into the TIPA.")) {
                    Button { importing = true } label: {
                        Label(selectedURL?.lastPathComponent ?? "Choose File", systemImage: "doc.badge.plus")
                    }
                    if let selectedURL {
                        Button { Task { await uploadToGitHub(selectedURL) } } label: {
                            if isUploading { ProgressView() } else { Label("Upload", systemImage: "icloud.and.arrow.up") }
                        }
                        .disabled(isUploading)
                    }
                }
                Section(header: Text("Connection")) {
                    HStack {
                        Label(SecureTokenStore.load().isEmpty ? "GitHub token not configured" : "GitHub token configured", systemImage: SecureTokenStore.load().isEmpty ? "exclamationmark.triangle" : "checkmark.shield.fill")
                        Spacer()
                    }
                    Text("Configure the token once in Settings. Use a fine-grained token limited to the NextSolution repository with Contents: Read and write.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                if !resultText.isEmpty {
                    Section(header: Text("Last Result")) { Text(resultText).font(.footnote).textSelection(.enabled) }
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

    private func uploadToGitHub(_ url: URL) async {
        let token = SecureTokenStore.load()
        guard !token.isEmpty else {
            resultText = "GitHub upload token is not configured. Open Settings in this app first."
            return
        }
        isUploading = true
        defer { isUploading = false }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 40 * 1024 * 1024 else {
                resultText = "This upload method is intended for files up to 40 MB."
                return
            }
            let safeName = sanitize(url.lastPathComponent)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let path = "transfer/uploads/\(formatter.string(from: Date()))-\(safeName)"
            let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            guard let apiURL = URL(string: "https://api.github.com/repos/\(githubRepo)/contents/\(encodedPath)") else { throw URLError(.badURL) }

            let json: [String: Any] = [
                "message": "Upload \(safeName) from NextSolution Transfer",
                "content": data.base64EncodedString(),
                "branch": "main"
            ]
            var request = URLRequest(url: apiURL)
            request.httpMethod = "PUT"
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.timeoutInterval = 180
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("NextSolution-Transfer", forHTTPHeaderField: "User-Agent")

            let (responseData, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status) {
                resultText = "Uploaded successfully.\n\nPath: \(path)\n\nTell ChatGPT this path and it can fetch the file from your repo."
                selectedURL = nil
            } else {
                let message = (try? JSONSerialization.jsonObject(with: responseData) as? [String: Any])?["message"] as? String
                resultText = "GitHub returned HTTP \(status): \(message ?? "Unknown error")"
            }
        } catch {
            resultText = "Upload failed: \(error.localizedDescription)"
        }
    }

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }.reduce("") { $0 + String($1) }
    }
}

struct SettingsView: View {
    @State private var token = SecureTokenStore.load()
    @State private var savedMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Download Feed")) {
                    HStack { Text("Server"); Spacer(); Text("nextsolution.app").foregroundColor(.secondary) }
                    Text(feedURLString).font(.caption.monospaced()).textSelection(.enabled)
                }
                Section(header: Text("GitHub Upload Token"), footer: Text("Use a fine-grained GitHub personal access token restricted to zeshan0727/NextSolution with Repository permissions → Contents: Read and write. It is stored in iOS Keychain on this device.")) {
                    SecureField("Fine-grained token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    Button("Save Token") {
                        SecureTokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
                        token = SecureTokenStore.load()
                        savedMessage = token.isEmpty ? "Token cleared" : "Token saved in Keychain"
                    }
                    if !SecureTokenStore.load().isEmpty {
                        Button("Clear Token", role: .destructive) {
                            SecureTokenStore.delete(); token = ""; savedMessage = "Token cleared"
                        }
                    }
                    if !savedMessage.isEmpty { Text(savedMessage).font(.caption).foregroundColor(.secondary) }
                }
                Section(header: Text("Workflow")) {
                    Text("Downloads: validated DEBs/TIPAs published by the NextSolution build pipeline appear here automatically after Refresh.\n\nUploads: choose a file in the Upload tab and it is committed to transfer/uploads/ on the website repository. Then tell ChatGPT the displayed path so it can retrieve it directly.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
