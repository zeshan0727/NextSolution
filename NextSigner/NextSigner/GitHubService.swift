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
        progress: @Sendable (Double) async -> Void
    ) async throws -> DispatchResponse? {
        guard configuration.isValid else { throw NextSignerError.invalidConfiguration }

        let release = try await ensureStagingRelease()
        let safeName = makeStagingAssetName(original: ipaURL.lastPathComponent)
        try await deleteExistingAsset(named: safeName, from: release)
        await progress(0.15)
        try await uploadAsset(fileURL: ipaURL, name: safeName, release: release)
        await progress(0.85)
        let dispatch = try await dispatchSigningWorkflow(
            assetName: safeName,
            appName: appName,
            bundleID: bundleID
        )
        await progress(1.0)
        return dispatch
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

    private func deleteExistingAsset(named name: String, from release: Release) async throws {
        guard let asset = release.assets.first(where: { $0.name == name }) else { return }
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases/assets/\(asset.id)")
        let (data, response) = try await session.data(for: request(url: url, method: "DELETE"))
        try validate(response: response, data: data, accepted: [204])
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

    private func dispatchSigningWorkflow(assetName: String, appName: String, bundleID: String) async throws -> DispatchResponse? {
        let workflow = configuration.workflowFile.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? configuration.workflowFile
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/actions/workflows/\(workflow)/dispatches")
        let body: [String: Any] = [
            "ref": configuration.branch,
            "inputs": [
                "staging_asset": assetName,
                "requested_name": appName,
                "requested_bundle_id": bundleID
            ]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request(url: url, method: "POST", body: encoded))
        try validate(response: response, data: data, accepted: [200, 204])
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(DispatchResponse.self, from: data)
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
        req.timeoutInterval = 120
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

    private func makeStagingAssetName(original: String) -> String {
        let base = original.replacingOccurrences(of: " ", with: "-")
        let stamp = Int(Date().timeIntervalSince1970)
        return "\(stamp)-\(base.hasSuffix(".ipa") ? base : base + ".ipa")"
    }
}
