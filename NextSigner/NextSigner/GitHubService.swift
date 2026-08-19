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

        let requestID = UUID().uuidString.lowercased()
        await MainActor.run {
            PublishLogCenter.shared.begin(appName: appName, requestID: requestID)
        }

        do {
            await MainActor.run {
                PublishLogCenter.shared.append(stage: "GitHub", message: "Opening private signing inbox…")
            }
            let release = try await ensureStagingRelease()
            let stamp = Int(Date().timeIntervalSince1970)
            let ipaAsset = makeStagingAssetName(original: ipaURL.lastPathComponent, stamp: stamp, role: "app")

            await progress(0.08)
            await MainActor.run {
                PublishLogCenter.shared.append(stage: "Upload", message: "Uploading IPA/TIPA to the private inbox.")
            }
            try await uploadAsset(fileURL: ipaURL, name: ipaAsset, release: release)
            await progress(0.55)
            await MainActor.run {
                PublishLogCenter.shared.append(stage: "Upload", message: "Main app uploaded successfully.", kind: .success)
            }

            var iconAsset = ""
            if let customIconURL {
                await MainActor.run {
                    PublishLogCenter.shared.append(stage: "Icon", message: "Uploading selected custom icon.")
                }
                iconAsset = makeStagingAssetName(original: customIconURL.lastPathComponent, stamp: stamp, role: "icon")
                try await uploadAsset(fileURL: customIconURL, name: iconAsset, release: release)
                await MainActor.run {
                    PublishLogCenter.shared.append(stage: "Icon", message: "Custom icon uploaded.", kind: .success)
                }
            }
            await progress(0.65)

            var tweakAssets: [String] = []
            for (index, url) in tweakURLs.enumerated() {
                await MainActor.run {
                    PublishLogCenter.shared.append(stage: "Tweaks", message: "Uploading \(url.lastPathComponent).")
                }
                let assetName = makeStagingAssetName(original: url.lastPathComponent, stamp: stamp, role: "tweak\(index + 1)")
                try await uploadAsset(fileURL: url, name: assetName, release: release)
                tweakAssets.append(assetName)
                let fraction = Double(index + 1) / Double(max(tweakURLs.count, 1))
                await progress(0.65 + (0.20 * fraction))
            }
            if !tweakAssets.isEmpty {
                await MainActor.run {
                    PublishLogCenter.shared.append(stage: "Tweaks", message: "All tweak attachments uploaded.", kind: .success)
                }
            }

            let tweakJSONData = try JSONSerialization.data(withJSONObject: tweakAssets)
            let tweakJSON = String(data: tweakJSONData, encoding: .utf8) ?? "[]"
            await MainActor.run {
                PublishLogCenter.shared.append(stage: "Queue", message: "Sending publish request to GitHub Actions.")
            }
            let dispatch = try await dispatchSigningWorkflow(
                requestID: requestID,
                assetName: ipaAsset,
                appName: appName,
                bundleID: bundleID,
                customIconAsset: iconAsset,
                tweakAssetsJSON: tweakJSON,
                duplicateSigning: duplicateSigning,
                injectExtensions: injectExtensions,
                weakInjection: weakInjection
            )
            await progress(0.86)
            await MainActor.run {
                PublishLogCenter.shared.append(stage: "Queue", message: "GitHub accepted the request. Waiting for backend signing…", kind: .success)
            }

            try await waitForPublishStatus(
                requestID: requestID,
                releaseID: release.id,
                progress: progress
            )
            await progress(1.0)
            return dispatch
        } catch {
            await MainActor.run {
                if PublishLogCenter.shared.isRunning {
                    PublishLogCenter.shared.fail(error.localizedDescription)
                }
            }
            throw error
        }
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

    /// Signing uses repository_dispatch so the fine-grained PAT never needs to call
    /// the Actions workflow-dispatch endpoint directly.
    private func dispatchSigningWorkflow(
        requestID: String,
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
                "request_id": requestID,
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

    private func waitForPublishStatus(
        requestID: String,
        releaseID: Int,
        progress: @Sendable (Double) async -> Void
    ) async throws {
        let statusName = "status-\(requestID).json"
        let deadline = Date().addingTimeInterval(35 * 60)
        let started = Date()
        var waitingMessageShown = false

        while Date() < deadline {
            if let status = try await fetchPublishStatus(releaseID: releaseID, assetName: statusName) {
                await MainActor.run {
                    PublishLogCenter.shared.apply(status)
                }
                await progress(progressValue(for: status.stage, state: status.state))

                switch status.state.lowercased() {
                case "success":
                    return
                case "failed", "failure":
                    let detail = status.runURL.map { "\(status.message) Run: \($0)" } ?? status.message
                    throw NSError(
                        domain: "NextSigner.Publish",
                        code: 3001,
                        userInfo: [NSLocalizedDescriptionKey: "\(status.stage): \(detail)"]
                    )
                default:
                    break
                }
            } else if !waitingMessageShown && Date().timeIntervalSince(started) > 15 {
                waitingMessageShown = true
                await MainActor.run {
                    PublishLogCenter.shared.append(stage: "Queue", message: "GitHub runner is starting. This can take a little while.")
                }
            }

            try await Task.sleep(nanoseconds: 2_000_000_000)
        }

        throw NSError(
            domain: "NextSigner.Publish",
            code: 3002,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for the GitHub signing workflow after 35 minutes."]
        )
    }

    private func fetchPublishStatus(releaseID: Int, assetName: String) async throws -> PublishStatusPayload? {
        var matchedAsset: Asset?

        // Always bypass caches and paginate the private inbox. The status asset can
        // be created after the first poll, and the inbox may contain more than 100
        // assets after failed or queued signing jobs.
        for page in 1...5 {
            let assetsURL = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases/\(releaseID)/assets?per_page=100&page=\(page)")
            var assetsRequest = request(url: assetsURL)
            assetsRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            assetsRequest.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
            assetsRequest.setValue("no-cache", forHTTPHeaderField: "Pragma")

            let (assetsData, assetsResponse) = try await session.data(for: assetsRequest)
            try validate(response: assetsResponse, data: assetsData)
            let assets = try JSONDecoder().decode([Asset].self, from: assetsData)

            if let asset = assets.first(where: { $0.name == assetName }) {
                matchedAsset = asset
                break
            }
            if assets.count < 100 { break }
        }

        guard let asset = matchedAsset else { return nil }

        let assetURL = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases/assets/\(asset.id)")
        var statusRequest = request(url: assetURL)
        statusRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        statusRequest.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
        statusRequest.setValue("no-cache", forHTTPHeaderField: "Pragma")
        statusRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await session.data(for: statusRequest)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(PublishStatusPayload.self, from: data)
    }

    private func progressValue(for stage: String, state: String) -> Double {
        if ["success", "failed", "failure"].contains(state.lowercased()) {
            return state.lowercased() == "success" ? 1.0 : 0.99
        }
        switch stage.lowercased() {
        case "received", "bridge": return 0.87
        case "validate": return 0.89
        case "download": return 0.90
        case "zsign": return 0.92
        case "customize": return 0.93
        case "sign": return 0.95
        case "metadata": return 0.96
        case "r2 upload": return 0.97
        case "r2 verify": return 0.98
        case "icon": return 0.985
        case "manifest": return 0.99
        case "site": return 0.995
        default: return 0.90
        }
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
