import Foundation

actor GitHubService {
    struct PublishResult: Equatable {
        let assetURL: String
        let manifestPath: String
        let installerURL: String
    }

    private struct Release: Decodable {
        let id: Int
        let tagName: String
        let uploadURL: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case id
            case tagName = "tag_name"
            case uploadURL = "upload_url"
            case assets
        }
    }

    private struct Asset: Decodable {
        let id: Int
        let name: String
        let browserDownloadURL: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private struct ContentFile: Decodable {
        let content: String
        let encoding: String
        let sha: String
    }

    private struct Catalog: Codable {
        var catalog: String
        var updated: String
        var apps: [CatalogApp]
    }

    private struct CatalogApp: Codable {
        var id: String
        var name: String
        var version: String
        var build: String
        var platform: String
        var minimumOS: String
        var bundleId: String
        var icon: String
        var manifest: String
        var available: Bool
        var status: String
    }

    private let session: URLSession
    private let token: String
    private let configuration: GitHubConfiguration
    private let apiVersion = "2022-11-28"
    private let releaseTag = "private-apps"

    init(token: String, configuration: GitHubConfiguration, session: URLSession = .shared) {
        self.token = token
        self.configuration = configuration
        self.session = session
    }

    func publishSignedIPA(
        _ signed: SignedAppResult,
        progress: @Sendable (Double) async -> Void
    ) async throws -> PublishResult {
        guard configuration.isValid else { throw NextSignerError.invalidConfiguration }

        try await verifyRepositoryAccess()
        await progress(0.08)

        var release = try await ensurePublishRelease()
        let slug = makeSlug(signed.appName)
        let assetName = "\(slug)-\(safeVersion(signed.version))-\(safeVersion(signed.build)).ipa"
        try await deleteExistingAsset(named: assetName, from: release)
        release = try await fetchRelease(tag: releaseTag)

        await progress(0.18)
        let uploaded = try await uploadAsset(fileURL: signed.ipaURL, name: assetName, release: release)
        await progress(0.72)

        let downloadURL = uploaded.browserDownloadURL
            ?? "https://github.com/\(configuration.owner)/\(configuration.repository)/releases/download/\(releaseTag)/\(assetName)"
        let manifestPath = "install/manifests/\(slug).plist"
        let manifest = makeManifest(signed: signed, downloadURL: downloadURL)
        try await putTextFile(path: manifestPath, content: manifest, message: "Publish \(signed.appName) OTA manifest")
        await progress(0.84)

        try await updateCatalog(signed: signed, slug: slug, manifestPath: "/\(manifestPath)")
        await progress(1.0)

        return PublishResult(
            assetURL: downloadURL,
            manifestPath: manifestPath,
            installerURL: "https://nextsolution.cc/install/"
        )
    }

    private func verifyRepositoryAccess() async throws {
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)")
        let (data, response) = try await session.data(for: request(url: url))
        try validate(response: response, data: data)
    }

    private func fetchRelease(tag: String) async throws -> Release {
        let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases/tags/\(encoded)")
        let (data, response) = try await session.data(for: request(url: url))
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private func ensurePublishRelease() async throws -> Release {
        if let release = try? await fetchRelease(tag: releaseTag) {
            return release
        }

        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases")
        let body: [String: Any] = [
            "tag_name": releaseTag,
            "target_commitish": configuration.branch,
            "name": "Next Solution Private Apps",
            "body": "Signed IPA assets published by Next Signer.",
            "draft": false,
            "prerelease": true,
            "make_latest": "false"
        ]
        let encoded = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request(url: url, method: "POST", body: encoded))
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private func deleteExistingAsset(named name: String, from release: Release) async throws {
        guard let asset = release.assets.first(where: { $0.name == name }) else { return }
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases/assets/\(asset.id)")
        let (data, response) = try await session.data(for: request(url: url, method: "DELETE"))
        try validate(response: response, data: data, accepted: [204])
    }

    private func uploadAsset(fileURL: URL, name: String, release: Release) async throws -> Asset {
        guard var components = URLComponents(string: release.uploadURL.components(separatedBy: "{").first ?? release.uploadURL) else {
            throw NextSignerError.malformedURL
        }
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { throw NextSignerError.malformedURL }

        var uploadRequest = request(url: url, method: "POST")
        uploadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: uploadRequest, fromFile: fileURL)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Asset.self, from: data)
    }

    private func updateCatalog(signed: SignedAppResult, slug: String, manifestPath: String) async throws {
        let path = "install/apps.json"
        let existing = try await fetchTextFile(path: path)
        var catalog: Catalog

        if let existing,
           let data = existing.text.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Catalog.self, from: data) {
            catalog = decoded
        } else {
            catalog = Catalog(catalog: "Next Solution Private Apps", updated: dateStamp(), apps: [])
        }

        let entry = CatalogApp(
            id: slug,
            name: signed.appName,
            version: signed.version,
            build: signed.build,
            platform: "iPhone",
            minimumOS: minimumOSLabel(signed.minimumOS),
            bundleId: signed.bundleID,
            icon: "/logo.png",
            manifest: manifestPath,
            available: true,
            status: "Ready to install"
        )

        if let index = catalog.apps.firstIndex(where: { $0.bundleId == signed.bundleID || $0.id == slug }) {
            catalog.apps[index] = entry
        } else {
            catalog.apps.insert(entry, at: 0)
        }
        catalog.updated = dateStamp()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(catalog)
        guard let text = String(data: data, encoding: .utf8) else { throw NextSignerError.invalidResponse }
        try await putTextFile(path: path, content: text + "\n", message: "Publish \(signed.appName) to private app catalog", knownSHA: existing?.sha)
    }

    private func makeManifest(signed: SignedAppResult, downloadURL: String) -> String {
        let escapedURL = xmlEscape(downloadURL)
        let bundle = xmlEscape(signed.bundleID)
        let build = xmlEscape(signed.build)
        let title = xmlEscape(signed.appName)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>items</key>
          <array>
            <dict>
              <key>assets</key>
              <array>
                <dict>
                  <key>kind</key>
                  <string>software-package</string>
                  <key>url</key>
                  <string>\(escapedURL)</string>
                </dict>
              </array>
              <key>metadata</key>
              <dict>
                <key>bundle-identifier</key>
                <string>\(bundle)</string>
                <key>bundle-version</key>
                <string>\(build)</string>
                <key>kind</key>
                <string>software</string>
                <key>title</key>
                <string>\(title)</string>
              </dict>
            </dict>
          </array>
        </dict>
        </plist>
        """
    }

    private func fetchTextFile(path: String) async throws -> (text: String, sha: String)? {
        let encodedPath = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/contents/\(encodedPath)?ref=\(configuration.branch)")
        let (data, response) = try await session.data(for: request(url: url))
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        try validate(response: response, data: data)
        let file = try JSONDecoder().decode(ContentFile.self, from: data)
        guard file.encoding == "base64" else { throw NextSignerError.invalidResponse }
        let compact = file.content.replacingOccurrences(of: "\n", with: "")
        guard let raw = Data(base64Encoded: compact), let text = String(data: raw, encoding: .utf8) else {
            throw NextSignerError.invalidResponse
        }
        return (text, file.sha)
    }

    private func putTextFile(path: String, content: String, message: String, knownSHA: String? = nil) async throws {
        let current = knownSHA == nil ? try await fetchTextFile(path: path) : nil
        let sha = knownSHA ?? current?.sha
        let encodedPath = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/contents/\(encodedPath)")
        var body: [String: Any] = [
            "message": message,
            "content": Data(content.utf8).base64EncodedString(),
            "branch": configuration.branch
        ]
        if let sha { body["sha"] = sha }
        let encoded = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request(url: url, method: "PUT", body: encoded))
        try validate(response: response, data: data)
    }

    private func request(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue(apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        req.timeoutInterval = 180
        return req
    }

    private func apiURL(_ path: String) throws -> URL {
        guard let url = URL(string: "https://api.github.com\(path)") else { throw NextSignerError.malformedURL }
        return url
    }

    private func validate(response: URLResponse, data: Data, accepted: Set<Int>? = nil) throws {
        guard let http = response as? HTTPURLResponse else { throw NextSignerError.invalidResponse }
        let allowed = accepted ?? Set(200...299)
        guard allowed.contains(http.statusCode) else {
            let message: String
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let apiMessage = object["message"] as? String {
                message = apiMessage
            } else {
                message = String(data: data, encoding: .utf8) ?? "Unknown error"
            }
            throw NextSignerError.http(http.statusCode, message)
        }
    }

    private func makeSlug(_ value: String) -> String {
        let lowered = value.lowercased()
        let allowed = CharacterSet.alphanumerics
        var result = lowered.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        while result.contains(where: { _ in false }) { break }
        var text = String(result)
        while text.contains("--") { text = text.replacingOccurrences(of: "--", with: "-") }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return text.isEmpty ? "signed-app" : text
    }

    private func safeVersion(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let result = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        return String(result)
    }

    private func minimumOSLabel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "ios" else { return "iOS" }
        if trimmed.lowercased().hasPrefix("ios") { return trimmed }
        return "iOS \(trimmed)+"
    }

    private func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
