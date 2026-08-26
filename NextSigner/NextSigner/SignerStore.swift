import Foundation
import Combine

@MainActor
final class SignerStore: ObservableObject {
    @Published var request = SignRequest()
    @Published var configuration: GitHubConfiguration
    @Published var token: String
    @Published var tokenIsStored: Bool
    @Published var isWorking = false
    @Published var progress: Double = 0
    @Published var activeJob: SigningJob?
    @Published var errorMessage: String?
    @Published var successMessage: String?

    @Published var libraryApps: [PublishedApp] = []
    @Published var libraryIsLoading = false
    @Published var libraryErrorMessage: String?
    @Published var libraryMessage: String?
    @Published var libraryManagingAppID: String?

    private let defaults = UserDefaults.standard
    private let tokenAccount = "github-token"
    private var duplicateBaseBundleID: String?
    private var duplicateBaseName: String?

    init() {
        configuration = GitHubConfiguration(
            owner: UserDefaults.standard.string(forKey: "githubOwner") ?? "zeshan0727",
            repository: UserDefaults.standard.string(forKey: "githubRepository") ?? "NextSolution",
            branch: UserDefaults.standard.string(forKey: "githubBranch") ?? "main",
            workflowFile: UserDefaults.standard.string(forKey: "githubWorkflow") ?? "nextsigner-sign-publish.yml"
        )
        let stored = KeychainStore.load(account: tokenAccount) ?? ""
        token = stored
        tokenIsStored = !stored.isEmpty
    }

    func persistConfiguration() {
        defaults.set(configuration.owner, forKey: "githubOwner")
        defaults.set(configuration.repository, forKey: "githubRepository")
        defaults.set(configuration.branch, forKey: "githubBranch")
        defaults.set(configuration.workflowFile, forKey: "githubWorkflow")
    }

    func saveToken() {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                KeychainStore.delete(account: tokenAccount)
                tokenIsStored = false
            } else {
                try KeychainStore.save(trimmed, account: tokenAccount)
                token = trimmed
                tokenIsStored = true
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not save the GitHub token: \(error.localizedDescription)"
        }
    }

    func importIPA(from pickedURL: URL) {
        do {
            clearSelectedIPA(removeMessage: false)
            let localURL = try copyIntoPrivateStaging(pickedURL, subfolder: "Apps")
            request.ipaURL = localURL
            request.appName = suggestedAppName(from: localURL.lastPathComponent)
            request.bundleID = suggestedBundleID(from: request.appName)
            errorMessage = nil
            successMessage = nil
        } catch {
            errorMessage = "Unable to import IPA: \(error.localizedDescription)"
        }
    }

    func importCustomIcon(from pickedURL: URL) {
        let ext = pickedURL.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg"].contains(ext) else {
            errorMessage = "Choose a PNG, JPG or JPEG image for the custom app icon."
            return
        }
        do {
            if let old = request.customIconURL { try? FileManager.default.removeItem(at: old) }
            request.customIconURL = try copyIntoPrivateStaging(pickedURL, subfolder: "Icons")
            errorMessage = nil
        } catch {
            errorMessage = "Unable to import the custom icon: \(error.localizedDescription)"
        }
    }

    func importCustomIconPNGData(_ data: Data) {
        guard !data.isEmpty else {
            errorMessage = "The selected photo could not be converted into an app icon."
            return
        }
        do {
            if let old = request.customIconURL { try? FileManager.default.removeItem(at: old) }
            let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("NextSignerInbox", isDirectory: true)
                .appendingPathComponent("Icons", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent("photo-icon-\(UUID().uuidString).png")
            try data.write(to: destination, options: .atomic)
            request.customIconURL = destination
            errorMessage = nil
        } catch {
            errorMessage = "Unable to use the selected photo as an icon: \(error.localizedDescription)"
        }
    }

    func clearCustomIcon() {
        if let url = request.customIconURL { try? FileManager.default.removeItem(at: url) }
        request.customIconURL = nil
    }

    func importTweaks(from pickedURLs: [URL]) {
        let accepted = pickedURLs.filter { ["dylib", "deb"].contains($0.pathExtension.lowercased()) }
        guard !accepted.isEmpty else {
            errorMessage = "Choose one or more .dylib files or .deb tweak packages containing dylibs."
            return
        }
        do {
            for url in accepted {
                let local = try copyIntoPrivateStaging(url, subfolder: "Tweaks")
                request.tweakURLs.append(local)
            }
            errorMessage = nil
        } catch {
            errorMessage = "Unable to import tweak files: \(error.localizedDescription)"
        }
    }

    func removeTweak(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        request.tweakURLs.removeAll { $0 == url }
    }

    func setDuplicateSigning(_ enabled: Bool) {
        guard enabled != request.duplicateSigning else { return }
        if enabled {
            duplicateBaseBundleID = request.bundleID
            duplicateBaseName = request.appName
            let base = request.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = String(Int(Date().timeIntervalSince1970) % 100000)
            request.bundleID = "\(base.isEmpty ? "com.nextsolution.signedapp" : base).copy\(suffix)"
            if !request.appName.hasSuffix(" Copy") {
                request.appName += " Copy"
            }
        } else {
            if let duplicateBaseBundleID { request.bundleID = duplicateBaseBundleID }
            if let duplicateBaseName { request.appName = duplicateBaseName }
            duplicateBaseBundleID = nil
            duplicateBaseName = nil
        }
        request.duplicateSigning = enabled
    }

    func clearSelectedIPA(removeMessage: Bool = true) {
        if let url = request.ipaURL { try? FileManager.default.removeItem(at: url) }
        if let url = request.customIconURL { try? FileManager.default.removeItem(at: url) }
        for url in request.tweakURLs { try? FileManager.default.removeItem(at: url) }
        request = SignRequest()
        duplicateBaseBundleID = nil
        duplicateBaseName = nil
        activeJob = nil
        progress = 0
        if removeMessage { successMessage = nil }
    }

    func signAndPublish() {
        guard !isWorking else { return }
        guard request.isReady else {
            errorMessage = "Choose an IPA and enter a valid app name and bundle identifier."
            return
        }
        guard configuration.isValid else {
            errorMessage = NextSignerError.invalidConfiguration.localizedDescription
            return
        }
        let currentToken = KeychainStore.load(account: tokenAccount) ?? token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentToken.isEmpty else {
            errorMessage = NextSignerError.missingToken.localizedDescription
            return
        }
        guard let ipaURL = request.ipaURL else { return }

        persistConfiguration()
        isWorking = true
        progress = 0
        errorMessage = nil
        successMessage = nil
        activeJob = SigningJob(
            sourceName: ipaURL.lastPathComponent,
            requestedBundleID: request.bundleID,
            requestedAppName: request.appName,
            stage: .preparing,
            detail: "Preparing app and signing options"
        )

        let service = GitHubService(token: currentToken, configuration: configuration)
        let snapshot = request

        Task {
            do {
                activeJob?.stage = .uploading
                let extras = snapshot.tweakURLs.count + (snapshot.customIconURL == nil ? 0 : 1)
                if snapshot.signingEnabled {
                    activeJob?.detail = extras == 0 ? "Uploading IPA to the private signing inbox" : "Uploading IPA and \(extras) customization file(s)"
                } else {
                    activeJob?.detail = "Uploading original IPA for Publish Only"
                }
                let response = try await service.uploadAndDispatch(
                    ipaURL: ipaURL,
                    appName: snapshot.appName,
                    bundleID: snapshot.bundleID,
                    customIconURL: snapshot.customIconURL,
                    tweakURLs: snapshot.tweakURLs,
                    signingEnabled: snapshot.signingEnabled,
                    duplicateSigning: snapshot.duplicateSigning,
                    injectExtensions: snapshot.injectTweaksIntoExtensions,
                    weakInjection: snapshot.weakTweakInjection,
                    progress: { value in
                        await MainActor.run { self.progress = value }
                    }
                )
                activeJob?.stage = .queued
                if let runURL = response?.htmlURL, !runURL.isEmpty {
                    activeJob?.detail = "Advanced signing and publishing started: \(runURL)"
                } else {
                    activeJob?.detail = "Advanced signing and publishing workflow queued"
                }
                successMessage = snapshot.signingEnabled
                    ? "Signed and published successfully through Cloudflare R2."
                    : "Published successfully without re-signing through Cloudflare R2."
                progress = 1
            } catch {
                activeJob?.stage = .failed
                activeJob?.detail = error.localizedDescription
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    func refreshLibrary() async {
        libraryIsLoading = true
        libraryErrorMessage = nil
        defer { libraryIsLoading = false }
        do {
            let currentToken = KeychainStore.load(account: tokenAccount) ?? token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !currentToken.isEmpty && configuration.isValid {
                let service = GitHubService(token: currentToken, configuration: configuration)
                libraryApps = try await service.fetchPublishedCatalog().apps
            } else {
                var components = URLComponents(string: "https://nextjailbreak.com/install/apps.json")!
                components.queryItems = [URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970)))]
                guard let url = components.url else { throw NextSignerError.libraryUnavailable }
                var webRequest = URLRequest(url: url)
                webRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                webRequest.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: webRequest)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw NextSignerError.libraryUnavailable
                }
                libraryApps = try JSONDecoder().decode(PublishedCatalog.self, from: data).apps
            }
        } catch {
            libraryErrorMessage = error.localizedDescription
        }
    }

    func manageLibrary(app: PublishedApp, action: LibraryAction) async {
        guard libraryManagingAppID == nil else { return }
        guard configuration.isValid else {
            libraryErrorMessage = NextSignerError.invalidConfiguration.localizedDescription
            return
        }
        let currentToken = KeychainStore.load(account: tokenAccount) ?? token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentToken.isEmpty else {
            libraryErrorMessage = NextSignerError.missingToken.localizedDescription
            return
        }

        libraryManagingAppID = app.id
        libraryMessage = nil
        libraryErrorMessage = nil
        defer { libraryManagingAppID = nil }

        do {
            let service = GitHubService(token: currentToken, configuration: configuration)
            try await service.dispatchLibraryAction(appID: app.id, action: action)

            switch action {
            case .cleanOldVersions:
                libraryMessage = "Cleanup requested for \(app.name). GitHub will keep the current build and remove older R2 versions."
            case .deleteApp:
                // Remove immediately from the visible list, then verify against the repository
                // catalog until the background workflow has committed the deletion.
                libraryApps.removeAll { $0.id == app.id }
                libraryMessage = "Deleting \(app.name)… waiting for GitHub and Cloudflare R2."

                var verified = false
                for _ in 0..<45 {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    let catalog = try await service.fetchPublishedCatalog()
                    if !catalog.apps.contains(where: { $0.id == app.id }) {
                        libraryApps = catalog.apps
                        verified = true
                        break
                    }
                }

                if verified {
                    libraryMessage = "Deleted \(app.name) from the site and Cloudflare R2."
                } else {
                    await refreshLibrary()
                    throw NSError(
                        domain: "NextSigner",
                        code: 2001,
                        userInfo: [NSLocalizedDescriptionKey: "Deletion was accepted by GitHub but did not finish within 90 seconds. Pull to refresh or check the repository Actions log."]
                    )
                }
            }
        } catch {
            libraryErrorMessage = error.localizedDescription
            await refreshLibrary()
        }
    }

    private func copyIntoPrivateStaging(_ source: URL, subfolder: String) throws -> URL {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextSignerInbox", isDirectory: true)
            .appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let sanitized = source.lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let destination = folder.appendingPathComponent("\(UUID().uuidString)-\(sanitized)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func suggestedAppName(from filename: String) -> String {
        var value = (filename as NSString).deletingPathExtension
        value = value.replacingOccurrences(of: "_", with: " ")
        value = value.replacingOccurrences(of: "-", with: " ")
        return value.split(separator: " ").prefix(4).joined(separator: " ")
    }

    private func suggestedBundleID(from appName: String) -> String {
        let slug = appName.lowercased().unicodeScalars.compactMap { scalar -> Character? in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(String(scalar)) }
            return nil
        }
        let suffix = String(slug)
        return "com.nextsolution.\(suffix.isEmpty ? "signedapp" : suffix)"
    }
}
