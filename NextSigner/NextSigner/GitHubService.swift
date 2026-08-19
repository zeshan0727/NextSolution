import Foundation

actor GitHubService {
    struct Release: Decodable {
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

    struct Asset: Decodable {
        let id: Int
        let name: String
    }

    struct DispatchResponse: Decodable {
        let workflowRunID: Int?
        let htmlURL: String?

        enum CodingKeys: String, CodingKey {
            case workflowRunID = "workflow_run_id"
            case htmlURL = "html_url"
        }
    }

    private struct RepositoryContentFile: Decodable {
        let content: String
        let encoding: String
    }

    private let session: URLSession
    private let token: String
    private let configuration: GitHubConfiguration
    private let apiVersion = "2026-03-10"
    private let stagingTag = "nextsigner-inbox"

    init(token: String, configuration: GitHubConfiguration, session: URLSession = .shared) {
        self.token = token
        self.configuration = configuration
        self.session = session
    }

    func uploadAndDispatch(
        ipaURL: URL,
        appName: String,
        bundleID: String,
        customIconURL: URL?,
        tweakURLs: [URL],
        duplicateSigning: Bool,
        injectExtensions: Bool,
        weakInjection: Bool,
        progress: @Sendable (Double) async -> Void
    ) async throws -> DispatchResponse? {
        guard configuration.isValid else { throw NextSignerError.invalidConfiguration }

        let release = try await ensureStagingRelease()
        let stamp = Int(Date().timeIntervalSince1970)
        let ipaAsset = makeStagingAssetName(original: ipaURL.lastPathComponent, stamp: stamp, role: "app")

        await progress(0.08)
        try await uploadAsset(fileURL: ipaURL, name: ipaAsset, release: release)
        await progress(0.55)

        var iconAsset = ""
        if let customIconURL {
            iconAsset = makeStagingAssetName(original: customIconURL.lastPathComponent, stamp: stamp, role: "icon")
            try await uploadAsset(fileURL: customIconURL, name: iconAsset, release: release)
        }
        await progress(0.65)

        var tweakAssets: [String] = []
        for (index, url) in tweakURLs.enumerated() {
            let assetName = makeStagingAssetName(original: url.lastPathComponent, stamp: stamp, role: "tweak\(index + 1)")
            try await uploadAsset(fileURL: url, name: assetName, release: release)
            tweakAssets.append(assetName)
            let fraction = Double(index + 1) / Double(max(tweakURLs.count, 1))
            await progress(0.65 + (0.20 * fraction))
        }

        let tweakJSONData = try JSONSerialization.data(withJSONObject: tweakAssets)
        let tweakJSON = String(data: tweakJSONData, encoding: .utf8) ?? "[]"
        let dispatch = try await dispatchSigningWorkflow(
            assetName: ipaAsset,
            appName: appName,
            bundleID: bundleID,
            customIconAsset: iconAsset,
            tweakAssetsJSON: tweakJSON,
            duplicateSigning: duplicateSigning,
            injectExtensions: injectExtensions,
            weakInjection: weakInjection
        )
        await progress(1.0)
        return dispatch
    }

    /// Library management uses repository_dispatch instead of the Actions workflow
    /// dispatch endpoint so a fine-grained PAT does not need Actions: write access.
    func dispatchLibraryAction(appID: String, action: LibraryAction) async throws {
        guard configuration.isValid else { throw NextSignerError.invalidConfiguration }
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/dispatches")
        let body: [String: Any] = [
            "event_type": "nextsigner_library_manage",
            "client_payload": [
                "app_id": appID,
                "mode": action.rawValue
            ]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request(url: url, method: "POST", body: encoded))
        try validate(response: response, data: data, accepted: [204])
    }

    /// Reads the catalog from the repository itself instead of GitHub Pages/CDN so
    /// deletion can be verified immediately after the management workflow commits.
    func fetchPublishedCatalog() async throws -> PublishedCatalog {
        guard configuration.isValid else { throw NextSignerError.invalidConfiguration }
        let ref = configuration.branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? configuration.branch
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/contents/install/apps.json?ref=\(ref)")
        let (data, response) = try await session.data(for: request(url: url))
        try validate(response: response, data: data)
        let file = try JSONDecoder().decode(RepositoryContentFile.self, from: data)
        guard file.encoding.lowercased() == "base64" else { throw NextSignerError.libraryUnavailable }
        let compact = file.content.filter { !$0.isWhitespace }
        guard let decoded = Data(base64Encoded: compact) else { throw NextSignerError.libraryUnavailable }
        return try JSONDecoder().decode(PublishedCatalog.self, from: decoded)
    }

    private func ensureStagingRelease() async throws -> Release {
        let releasesURL = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases?per_page=100")
        let (data, response) = try await session.data(for: request(url: releasesURL))
        try validate(response: response, data: data)

        if let releases = try? JSONDecoder().decode([Release].self, from: data),
           let existing = releases.first(where: { $0.tagName == stagingTag }) {
            return existing
        }

        let createURL = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases")
        let body: [String: Any] = [
            "tag_name": stagingTag,
            "target_commitish": configuration.branch,
            "name": "Next Signer Inbox",
            "body": "Private staging release used by the Next Signer app.",
            "draft": true,
            "prerelease": true,
            "make_latest": "false"
        ]
        let encoded = try JSONSerialization.data(withJSONObject: body)
        let (createData, createResponse) = try await session.data(for: request(url: createURL, method: "POST", body: encoded))
        try validate(response: createResponse, data: createData)
        return try JSONDecoder().decode(Release.self, from: createData)
    }

    private func uploadAsset(fileURL: URL, name: String, release: Release) async throws {
        guard var components = URLComponents(string: release.uploadURL.components(separatedBy: "{").first ?? release.uploadURL) else {
            throw NextSignerError.malformedURL
        }
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { throw NextSignerError.malformedURL }

        var uploadRequest = request(url: url, method: "POST")
        uploadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: uploadRequest, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NextSignerError.uploadFailed
        }
    }

    /// Signing also uses repository_dispatch. A tiny bridge workflow receives this
    /// event and starts the existing signing workflow using GitHub's own GITHUB_TOKEN.
    /// This avoids the fine-grained PAT 403 from /actions/workflows/.../dispatches.
    private func dispatchSigningWorkflow(
        assetName: String,
        appName: String,
        bundleID: String,
        customIconAsset: String,
        tweakAssetsJSON: String,
        duplicateSigning: Bool,
        injectExtensions: Bool,
        weakInjection: Bool
    ) async throws -> DispatchResponse? {
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/dispatches")
        let body: [String: Any] = [
            "event_type": "nextsigner_sign_publish",
            "client_payload": [
                "staging_asset": assetName,
                "requested_name": appName,
                "requested_bundle_id": bundleID,
                "custom_icon_asset": customIconAsset,
                "tweak_assets_json": tweakAssetsJSON,
                "duplicate_signing": duplicateSigning ? "true" : "false",
                "inject_extensions": injectExtensions ? "true" : "false",
                "weak_injection": weakInjection ? "true" : "false"
            ]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request(url: url, method: "POST", body: encoded))
        try validate(response: response, data: data, accepted: [204])
        return nil
    }

    private func request(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue(apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.timeoutInterval = 180
        return req
    }

    private func apiURL(_ path: String) throws -> URL {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw NextSignerError.malformedURL
        }
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

    private func makeStagingAssetName(original: String, stamp: Int, role: String) -> String {
        let safe = original
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return "\(stamp)-\(role)-\(safe)"
    }
}
