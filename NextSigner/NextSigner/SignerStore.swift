import Foundation

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

    private let defaults = UserDefaults.standard
    private let tokenAccount = "github-token"

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
            let localURL = try copyIntoPrivateStaging(pickedURL)
            request.ipaURL = localURL
            if request.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                request.appName = suggestedAppName(from: localURL.lastPathComponent)
            }
            if request.bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                request.bundleID = suggestedBundleID(from: request.appName)
            }
            errorMessage = nil
            successMessage = nil
        } catch {
            errorMessage = "Unable to import IPA: \(error.localizedDescription)"
        }
    }

    func clearSelectedIPA() {
        if let url = request.ipaURL {
            try? FileManager.default.removeItem(at: url)
        }
        request.ipaURL = nil
        activeJob = nil
        progress = 0
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
            detail: "Preparing secure upload"
        )

        let service = GitHubService(token: currentToken, configuration: configuration)
        let appName = request.appName
        let bundleID = request.bundleID

        Task {
            do {
                activeJob?.stage = .uploading
                activeJob?.detail = "Uploading IPA to the private signing inbox"
                let response = try await service.uploadAndDispatch(
                    ipaURL: ipaURL,
                    appName: appName,
                    bundleID: bundleID,
                    progress: { value in
                        await MainActor.run {
                            self.progress = value
                        }
                    }
                )
                activeJob?.stage = .queued
                if let runURL = response?.htmlURL, !runURL.isEmpty {
                    activeJob?.detail = "Signing and publishing started: \(runURL)"
                } else {
                    activeJob?.detail = "Signing and publishing workflow queued"
                }
                successMessage = "Uploaded successfully. GitHub is now signing the IPA and publishing it to your private app page."
                progress = 1
            } catch {
                activeJob?.stage = .failed
                activeJob?.detail = error.localizedDescription
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func copyIntoPrivateStaging(_ source: URL) throws -> URL {
        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.stopAccessingSecurityScopedResource() }
        }

        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextSignerInbox", isDirectory: true)
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
