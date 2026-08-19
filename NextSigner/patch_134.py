from pathlib import Path

service = Path('NextSigner/NextSigner/GitHubService.swift')
text = service.read_text()
old_fetch = '''    private func fetchPublishStatus(releaseID: Int, assetName: String) async throws -> PublishStatusPayload? {
        let assetsURL = try apiURL("/repos/\\(configuration.owner)/\\(configuration.repository)/releases/\\(releaseID)/assets?per_page=100")
        let (assetsData, assetsResponse) = try await session.data(for: request(url: assetsURL))
        try validate(response: assetsResponse, data: assetsData)
        let assets = try JSONDecoder().decode([Asset].self, from: assetsData)
        guard let asset = assets.first(where: { $0.name == assetName }) else { return nil }

        let assetURL = try apiURL("/repos/\\(configuration.owner)/\\(configuration.repository)/releases/assets/\\(asset.id)")
        var statusRequest = request(url: assetURL)
        statusRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        statusRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await session.data(for: statusRequest)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(PublishStatusPayload.self, from: data)
    }
'''
new_fetch = '''    private func fetchPublishStatus(releaseID: Int, assetName: String) async throws -> PublishStatusPayload? {
        var matchedAsset: Asset?

        // Always bypass caches and paginate the private inbox. The status asset can
        // be created after the first poll, and the inbox may contain more than 100
        // assets after failed or queued signing jobs.
        for page in 1...5 {
            let assetsURL = try apiURL("/repos/\\(configuration.owner)/\\(configuration.repository)/releases/\\(releaseID)/assets?per_page=100&page=\\(page)")
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

        let assetURL = try apiURL("/repos/\\(configuration.owner)/\\(configuration.repository)/releases/assets/\\(asset.id)")
        var statusRequest = request(url: assetURL)
        statusRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        statusRequest.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
        statusRequest.setValue("no-cache", forHTTPHeaderField: "Pragma")
        statusRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await session.data(for: statusRequest)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(PublishStatusPayload.self, from: data)
    }
'''
if old_fetch not in text:
    raise SystemExit('Expected fetchPublishStatus block was not found')
service.write_text(text.replace(old_fetch, new_fetch, 1))

project = Path('NextSigner/project.yml')
p = project.read_text()
if 'MARKETING_VERSION: "1.3.3"' not in p or 'CURRENT_PROJECT_VERSION: "16"' not in p:
    raise SystemExit('Unexpected Next Signer project version')
p = p.replace('MARKETING_VERSION: "1.3.3"', 'MARKETING_VERSION: "1.3.4"', 1)
p = p.replace('CURRENT_PROJECT_VERSION: "16"', 'CURRENT_PROJECT_VERSION: "17"', 1)
project.write_text(p)

index = Path('install/index.html')
html = index.read_text()
old = "const response=await fetch('/install/apps.json',{cache:'no-store'});"
new = "const response=await fetch('/install/apps.json?v='+Date.now(),{cache:'no-store',headers:{'Cache-Control':'no-cache'}});"
if old not in html:
    raise SystemExit('Expected installer catalog fetch was not found')
html = html.replace(old, new, 1)
if 'setInterval(loadCatalog,30000);' not in html:
    html = html.replace('    loadCatalog();\n', '    loadCatalog();\n    setInterval(loadCatalog,30000);\n', 1)
index.write_text(html)
