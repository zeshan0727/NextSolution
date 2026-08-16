import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

private let enhancedUploadRepo = "zeshan0727/NextSolution"

enum EnhancedPickerDestination: String, Identifiable {
    case files
    case photos
    case videos

    var id: String { rawValue }
}

enum EnhancedPhotoMediaKind {
    case photo
    case video

    var filter: PHPickerFilter {
        switch self {
        case .photo: return .images
        case .video: return .videos
        }
    }

    var preferredIdentifier: String {
        switch self {
        case .photo: return UTType.image.identifier
        case .video: return UTType.movie.identifier
        }
    }

    var fallbackName: String {
        switch self {
        case .photo: return "photo"
        case .video: return "video"
        }
    }
}

struct EnhancedPhotoLibraryPicker: UIViewControllerRepresentable {
    let kind: EnhancedPhotoMediaKind
    let onPick: (URL) -> Void
    let onCancel: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(kind: kind, onPick: onPick, onCancel: onCancel, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = kind.filter
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let kind: EnhancedPhotoMediaKind
        let onPick: (URL) -> Void
        let onCancel: () -> Void
        let onFailure: (String) -> Void

        init(
            kind: EnhancedPhotoMediaKind,
            onPick: @escaping (URL) -> Void,
            onCancel: @escaping () -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.kind = kind
            self.onPick = onPick
            self.onCancel = onCancel
            self.onFailure = onFailure
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                onCancel()
                return
            }

            let identifier: String
            if provider.hasItemConformingToTypeIdentifier(kind.preferredIdentifier) {
                identifier = kind.preferredIdentifier
            } else if kind == .video,
                      provider.hasItemConformingToTypeIdentifier(UTType.video.identifier) {
                identifier = UTType.video.identifier
            } else {
                DispatchQueue.main.async {
                    self.onFailure("The selected Photos item could not be read.")
                }
                return
            }

            provider.loadFileRepresentation(forTypeIdentifier: identifier) { sourceURL, error in
                if let error {
                    DispatchQueue.main.async {
                        self.onFailure("Photos picker failed: \(error.localizedDescription)")
                    }
                    return
                }

                guard let sourceURL else {
                    DispatchQueue.main.async {
                        self.onFailure("Photos did not return a usable file.")
                    }
                    return
                }

                do {
                    let localURL = try Self.copyIntoUploadCache(
                        sourceURL: sourceURL,
                        suggestedName: provider.suggestedName,
                        fallbackName: self.kind.fallbackName
                    )
                    DispatchQueue.main.async {
                        self.onPick(localURL)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.onFailure("Could not prepare selected media: \(error.localizedDescription)")
                    }
                }
            }
        }

        private static func copyIntoUploadCache(
            sourceURL: URL,
            suggestedName: String?,
            fallbackName: String
        ) throws -> URL {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PickedMedia", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            var name = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty { name = fallbackName }
            name = name
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
                .replacingOccurrences(of: ":", with: "_")

            if URL(fileURLWithPath: name).pathExtension.isEmpty,
               !sourceURL.pathExtension.isEmpty {
                name += ".\(sourceURL.pathExtension)"
            }

            let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        }
    }
}

struct EnhancedUploadView: View {
    @State private var activePicker: EnhancedPickerDestination?
    @State private var selectedURL: URL?
    @State private var isUploading = false
    @State private var resultText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Phone → NextSolution"),
                    footer: Text("Choose a normal file from Files, or select a photo/video directly from the Photos app. The selected item is copied locally first and then uploaded to transfer/uploads/.")
                ) {
                    Button {
                        activePicker = .files
                    } label: {
                        Label("Choose File", systemImage: "folder.fill.badge.plus")
                    }

                    Button {
                        activePicker = .photos
                    } label: {
                        Label("Choose Photo", systemImage: "photo.on.rectangle.angled")
                    }

                    Button {
                        activePicker = .videos
                    } label: {
                        Label("Choose Video", systemImage: "video.badge.plus")
                    }
                }

                if let selectedURL {
                    Section(header: Text("Selected")) {
                        HStack(spacing: 12) {
                            Image(systemName: selectedIcon(for: selectedURL))
                                .font(.title2)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(selectedURL.lastPathComponent)
                                    .lineLimit(1)
                                if let size = fileSizeDescription(selectedURL) {
                                    Text(size)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button(role: .destructive) {
                                self.selectedURL = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            Task { await uploadToGitHub(selectedURL) }
                        } label: {
                            if isUploading {
                                HStack {
                                    ProgressView()
                                    Text("Uploading…")
                                }
                            } else {
                                Label("Upload Selected Item", systemImage: "icloud.and.arrow.up.fill")
                            }
                        }
                        .disabled(isUploading)
                    }
                }

                Section(header: Text("Connection")) {
                    Label(
                        SecureTokenStore.load().isEmpty ? "GitHub token not configured" : "GitHub token configured",
                        systemImage: SecureTokenStore.load().isEmpty ? "exclamationmark.triangle" : "checkmark.shield.fill"
                    )
                    Text("Configure the token once in Settings. Use a fine-grained token limited to the NextSolution repository with Contents: Read and write.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if !resultText.isEmpty {
                    Section(header: Text("Last Result")) {
                        Text(resultText)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Upload")
            .sheet(item: $activePicker) { destination in
                switch destination {
                case .files:
                    DocumentPicker(
                        onPick: { url in
                            selectedURL = url
                            resultText = "Selected from Files: \(url.lastPathComponent)"
                            activePicker = nil
                        },
                        onCancel: {
                            activePicker = nil
                        }
                    )
                    .ignoresSafeArea()

                case .photos:
                    EnhancedPhotoLibraryPicker(
                        kind: .photo,
                        onPick: { url in
                            selectedURL = url
                            resultText = "Selected photo: \(url.lastPathComponent)"
                            activePicker = nil
                        },
                        onCancel: {
                            activePicker = nil
                        },
                        onFailure: { message in
                            resultText = message
                            activePicker = nil
                        }
                    )
                    .ignoresSafeArea()

                case .videos:
                    EnhancedPhotoLibraryPicker(
                        kind: .video,
                        onPick: { url in
                            selectedURL = url
                            resultText = "Selected video: \(url.lastPathComponent)"
                            activePicker = nil
                        },
                        onCancel: {
                            activePicker = nil
                        },
                        onFailure: { message in
                            resultText = message
                            activePicker = nil
                        }
                    )
                    .ignoresSafeArea()
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
                resultText = "Selected item is larger than the current 40 MB direct-upload limit."
                return
            }

            let safeName = sanitize(url.lastPathComponent)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd-HHmmss"

            let path = "transfer/uploads/\(formatter.string(from: Date()))-\(safeName)"
            let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path

            guard let apiURL = URL(string: "https://api.github.com/repos/\(enhancedUploadRepo)/contents/\(encodedPath)") else {
                throw URLError(.badURL)
            }

            let payload: [String: Any] = [
                "message": "Upload \(safeName) from NextSolution Transfer",
                "content": data.base64EncodedString(),
                "branch": "main"
            ]

            var request = URLRequest(url: apiURL)
            request.httpMethod = "PUT"
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            request.timeoutInterval = 180
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("NextSolution-Transfer", forHTTPHeaderField: "User-Agent")

            let (responseData, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if (200...299).contains(status) {
                resultText = "Uploaded successfully.\n\nPath: \(path)\n\nSend this path in ChatGPT so the file can be retrieved from the repo."
                selectedURL = nil
            } else {
                let message = (try? JSONSerialization.jsonObject(with: responseData) as? [String: Any])?["message"] as? String
                resultText = "GitHub returned HTTP \(status): \(message ?? "Unknown error")"
            }
        } catch {
            resultText = "Upload failed: \(error.localizedDescription)"
        }
    }

    private func selectedIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) { return "photo.fill" }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return "video.fill" }
            if type.conforms(to: .archive) { return "archivebox.fill" }
        }
        return "doc.fill"
    }

    private func fileSizeDescription(_ url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return name.unicodeScalars
            .map { allowed.contains($0) ? Character(String($0)) : "_" }
            .reduce("") { $0 + String($1) }
    }
}
