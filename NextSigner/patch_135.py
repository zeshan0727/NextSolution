from pathlib import Path
import re

# Models: publish-only is the default mode.
models = Path('NextSigner/NextSigner/Models.swift')
text = models.read_text()
if 'var signingEnabled = false' not in text:
    text = text.replace('    var weakTweakInjection = false\n', '    var weakTweakInjection = false\n    var signingEnabled = false\n', 1)
text = text.replace('''    var isReady: Bool {\n        ipaURL != nil && !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isValidBundleID\n    }\n''', '''    var isReady: Bool {\n        guard ipaURL != nil else { return false }\n        if signingEnabled {\n            return !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isValidBundleID\n        }\n        return true\n    }\n''', 1)
models.write_text(text)

# GitHub service: route mode + make release-status polling tolerant of clobber races.
service = Path('NextSigner/NextSigner/GitHubService.swift')
text = service.read_text()
text = text.replace('''        tweakURLs: [URL],\n        duplicateSigning: Bool,\n''', '''        tweakURLs: [URL],\n        signingEnabled: Bool,\n        duplicateSigning: Bool,\n''', 1)
text = text.replace('''                tweakAssetsJSON: tweakJSON,\n                duplicateSigning: duplicateSigning,\n''', '''                tweakAssetsJSON: tweakJSON,\n                signingEnabled: signingEnabled,\n                duplicateSigning: duplicateSigning,\n''', 1)
text = text.replace('''        tweakAssetsJSON: String,\n        duplicateSigning: Bool,\n''', '''        tweakAssetsJSON: String,\n        signingEnabled: Bool,\n        duplicateSigning: Bool,\n''', 1)
text = text.replace('''                "requested_bundle_id": bundleID,\n                "custom_icon_asset": customIconAsset,\n''', '''                "requested_bundle_id": bundleID,\n                "sign_enabled": signingEnabled ? "true" : "false",\n                "custom_icon_asset": customIconAsset,\n''', 1)

pattern = re.compile(r'''    private func fetchPublishStatus\(releaseID: Int, assetName: String\) async throws -> PublishStatusPayload\? \{.*?\n    \}\n\n    private func progressValue''', re.S)
replacement = '''    private func fetchPublishStatus(releaseID: Int, assetName: String) async throws -> PublishStatusPayload? {\n        // The workflow updates the same release asset with --clobber. GitHub briefly\n        // deletes the old backing blob before the replacement becomes readable.\n        // Treat 404/BlobNotFound as a transient refresh race instead of a publish error.\n        for attempt in 0..<8 {\n            var matchedAsset: Asset?\n\n            for page in 1...8 {\n                let nonce = String(Int(Date().timeIntervalSince1970 * 1000))\n                let assetsURL = try apiURL("/repos/\\(configuration.owner)/\\(configuration.repository)/releases/\\(releaseID)/assets?per_page=100&page=\\(page)&_ns=\\(nonce)")\n                var assetsRequest = request(url: assetsURL)\n                assetsRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData\n                assetsRequest.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")\n                assetsRequest.setValue("no-cache", forHTTPHeaderField: "Pragma")\n\n                let (assetsData, assetsResponse) = try await session.data(for: assetsRequest)\n                try validate(response: assetsResponse, data: assetsData)\n                let assets = try JSONDecoder().decode([Asset].self, from: assetsData)\n                if let asset = assets.first(where: { $0.name == assetName }) {\n                    matchedAsset = asset\n                    break\n                }\n                if assets.count < 100 { break }\n            }\n\n            guard let asset = matchedAsset else {\n                if attempt < 7 { try await Task.sleep(nanoseconds: 300_000_000) }\n                continue\n            }\n\n            let assetURL = try apiURL("/repos/\\(configuration.owner)/\\(configuration.repository)/releases/assets/\\(asset.id)?_ns=\\(UUID().uuidString)")\n            var statusRequest = request(url: assetURL)\n            statusRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")\n            statusRequest.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")\n            statusRequest.setValue("no-cache", forHTTPHeaderField: "Pragma")\n            statusRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData\n            let (data, response) = try await session.data(for: statusRequest)\n\n            if let http = response as? HTTPURLResponse {\n                if (200...299).contains(http.statusCode) {\n                    return try JSONDecoder().decode(PublishStatusPayload.self, from: data)\n                }\n                let body = String(data: data, encoding: .utf8) ?? ""\n                if http.statusCode == 404 || body.localizedCaseInsensitiveContains("BlobNotFound") {\n                    if attempt < 7 { try await Task.sleep(nanoseconds: 300_000_000) }\n                    continue\n                }\n            }\n\n            try validate(response: response, data: data)\n        }\n        return nil\n    }\n\n    private func progressValue'''
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit('Could not replace fetchPublishStatus')
service.write_text(text)

# Store: send selected mode and show mode-specific activity/success text.
store = Path('NextSigner/NextSigner/SignerStore.swift')
text = store.read_text()
text = text.replace('''                    tweakURLs: snapshot.tweakURLs,\n                    duplicateSigning: snapshot.duplicateSigning,\n''', '''                    tweakURLs: snapshot.tweakURLs,\n                    signingEnabled: snapshot.signingEnabled,\n                    duplicateSigning: snapshot.duplicateSigning,\n''', 1)
text = text.replace('''                activeJob?.detail = extras == 0 ? "Uploading IPA to the private signing inbox" : "Uploading IPA and \\(extras) customization file(s)"\n''', '''                if snapshot.signingEnabled {\n                    activeJob?.detail = extras == 0 ? "Uploading IPA to the private signing inbox" : "Uploading IPA and \\(extras) customization file(s)"\n                } else {\n                    activeJob?.detail = "Uploading original IPA for Publish Only"\n                }\n''', 1)
text = text.replace('''                successMessage = "Uploaded successfully. Next Signer is applying your options, signing the IPA and publishing it through Cloudflare R2."\n''', '''                successMessage = snapshot.signingEnabled\n                    ? "Signed and published successfully through Cloudflare R2."\n                    : "Published successfully without re-signing through Cloudflare R2."\n''', 1)
store.write_text(text)

# Root UI: Publish tab, signing toggle, profile tab, dynamic action button.
root = Path('NextSigner/NextSigner/NextSignerRootView.swift')
text = root.read_text()
text = text.replace('.tabItem { Label("Sign", systemImage: "signature") }', '.tabItem { Label("Publish", systemImage: "paperplane.fill") }', 1)
if 'SigningProfileView(store: store)' not in text:
    text = text.replace('''            NextSignerSettingsView(store: store)\n                .tabItem { Label("Settings", systemImage: "gearshape") }\n''', '''            SigningProfileView(store: store)\n                .tabItem { Label("Profiles", systemImage: "checkmark.seal.fill") }\n\n            NextSignerSettingsView(store: store)\n                .tabItem { Label("Settings", systemImage: "gearshape") }\n''', 1)
text = text.replace('''        VStack(alignment: .leading, spacing: 8) {\n            Label("Sign. Customize. Publish.", systemImage: "checkmark.seal.fill")\n                .font(.title2.bold())\n            Text("Sign IPA/TIPA files, create duplicate installs, replace icons from Photos or Files, attach tweak dylibs or DEBs, then publish through Cloudflare R2.")\n''', '''        VStack(alignment: .leading, spacing: 8) {\n            Label("Publish. Sign when needed.", systemImage: "paperplane.circle.fill")\n                .font(.title2.bold())\n            Text("Publish an IPA exactly as selected, or enable signing for bundle changes, duplicate installs, custom icons and tweak injection before publishing through Cloudflare R2.")\n''', 1)
marker = '''    private var advancedCard: some View {\n        GroupBox {\n            VStack(alignment: .leading, spacing: 14) {\n'''
if marker in text and 'Toggle("Enable signing"' not in text:
    text = text.replace(marker, marker + '''                Toggle("Enable signing", isOn: $store.request.signingEnabled)\n                    .fontWeight(.semibold)\n                Text(store.request.signingEnabled\n                     ? "Sign & Publish uses the saved P12 and provisioning profile."\n                     : "Publish Only uploads the IPA unchanged. It must already contain a usable signature if you want OTA installation to work.")\n                    .font(.caption)\n                    .foregroundStyle(.secondary)\n\n                Divider()\n\n''', 1)
text = text.replace('''                Button { store.signAndPublish() } label: {\n                    Label(store.isWorking ? "Signing & Publishing…" : "Sign & Publish", systemImage: "paperplane.fill")\n                        .frame(maxWidth: .infinity)\n                }\n''', '''                Button { store.signAndPublish() } label: {\n                    Label(\n                        store.isWorking\n                            ? (store.request.signingEnabled ? "Signing & Publishing…" : "Publishing…")\n                            : (store.request.signingEnabled ? "Sign & Publish" : "Publish"),\n                        systemImage: store.request.signingEnabled ? "signature" : "paperplane.fill"\n                    )\n                    .frame(maxWidth: .infinity)\n                }\n''', 1)
root.write_text(text)

# Version and Swift-Sodium package used for GitHub sealed-box secret encryption.
project = Path('NextSigner/project.yml')
p = project.read_text()
p = p.replace('MARKETING_VERSION: "1.3.4"', 'MARKETING_VERSION: "1.3.5"', 1)
p = p.replace('CURRENT_PROJECT_VERSION: "17"', 'CURRENT_PROJECT_VERSION: "18"', 1)
if '\npackages:\n' not in p:
    p = p.replace('settings:\n', 'packages:\n  Sodium:\n    url: https://github.com/jedisct1/swift-sodium.git\n    exactVersion: 0.11.0\nsettings:\n', 1)
if '      - package: Sodium\n' not in p:
    p = p.replace('''    sources:\n      - path: NextSigner\n''', '''    sources:\n      - path: NextSigner\n    dependencies:\n      - package: Sodium\n''', 1)
project.write_text(p)
