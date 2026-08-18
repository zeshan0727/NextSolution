import Foundation
import Combine

@MainActor
final class SignerStore: ObservableObject {
    @Published var request = SignRequest()
    @Published var configuration: GitHubConfiguration
    @Published var token: String
    @Published var tokenIsStored: Bool

    @Published var p12Password: String
    @Published var p12PasswordIsStored: Bool
    @Published var hasP12: Bool
    @Published var hasProvisioningProfile: Bool

    @Published var signedResult: SignedAppResult?
    @Published var isWorking = false
    @Published var progress: Double = 0
    @Published var activeJob: SigningJob?
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let defaults = UserDefaults.standard
    private let tokenAccount = "github-token"
    private let p12PasswordAccount = "p12-password"

    init() {
        configuration = GitHubConfiguration(
            owner: UserDefaults.standard.string(forKey: "githubOwner") ?? "zeshan0727",
            repository: UserDefaults.standard.string(forKey: "githubRepository") ?? "NextSolution",
            branch: UserDefaults.standard.string(forKey: "githubBranch") ?? "main"
        )

        let storedToken = KeychainStore.load(account: tokenAccount) ?? ""
        token = storedToken
        tokenIsStored = !storedToken.isEmpty

        let storedPassword = KeychainStore.load(account: p12PasswordAccount) ?? ""
        p12Password = storedPassword
        p12PasswordIsStored = !storedPassword.isEmpty
        hasP12 = CredentialStore.exists(.p12)
        hasProvisioningProfile = CredentialStore.exists(.provisioning)
    }

    var credentialsReady: Bool {
        hasP12 && hasProvisioningProfile && p12PasswordIsStored
    }

    func persistConfiguration() {
        defaults.set(configuration.owner, forKey: "githubOwner")
        defaults.set(configuration.repository, forKey: "githubRepository")
        defaults.set(configuration.branch, forKey: "githubBranch")
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

    func saveP12Password() {
        do {
            if p12Password.isEmpty {
                KeychainStore.delete(account: p12PasswordAccount)
                p12PasswordIsStored = false
            } else {
                try KeychainStore.save(p12Password, account: p12PasswordAccount)
                p12PasswordIsStored = true
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not save the certificate password: \(error.localizedDescription)"
        }
    }

    func importCredential(from pickedURL: URL, kind: CredentialStore.Kind) {
        do {
            try CredentialStore.importFile(from: pickedURL, as: kind)
            hasP12 = CredentialStore.exists(.p12)
            hasProvisioningProfile = CredentialStore.exists(.provisioning)
            successMessage = kind == .p12 ? "P12 certificate imported on this device." : "Provisioning profile imported on this device."
            errorMessage = nil
        } catch {
            errorMessage = "Unable to import signing credential: \(error.localizedDescription)"
        }
    }

    func importIPA(from pickedURL: URL) {
        do {
            let localURL = try copyIntoPrivateStaging(pickedURL)
            request.ipaURL = localURL
            signedResult = nil
            activeJob = nil
            progress = 0

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
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        request.ipaURL = nil
        signedResult = nil
        activeJob = nil
        progress = 0
        successMessage = nil
    }

    func signLocally() {
        guard !isWorking else { return }
        guard request.isReady, let ipaURL = request.ipaURL else {
            errorMessage = "Choose an IPA and enter a valid app name and bundle identifier."
            return
        }
        guard hasP12 else {
            errorMessage = LocalSignerError.missingCertificate.localizedDescription
            return
        }
        guard hasProvisioningProfile else {
            errorMessage = LocalSignerError.missingProvisioningProfile.localizedDescription
            return
        }
        let password = KeychainStore.load(account: p12PasswordAccount) ?? p12Password
        guard !password.isEmpty else {
            errorMessage = LocalSignerError.missingPassword.localizedDescription
            return
        }

        let appName = request.appName
        let bundleID = request.bundleID
        let p12URL = CredentialStore.url(for: .p12)
        let provisioningURL = CredentialStore.url(for: .provisioning)

        isWorking = true
        progress = 0.08
        errorMessage = nil
        successMessage = nil
        signedResult = nil
        activeJob = SigningJob(
            sourceName: ipaURL.lastPathComponent,
            requestedBundleID: bundleID,
            requestedAppName: appName,
            stage: .signing,
            detail: "Signing locally on this iPhone. Nothing is being uploaded."
        )

        Task {
            do {
                progress = 0.2
                let result = try await LocalSignerService().sign(
                    ipaURL: ipaURL,
                    requestedName: appName,
                    requestedBundleID: bundleID,
                    p12URL: p12URL,
                    provisioningURL: provisioningURL,
                    p12Password: password
                )

                signedResult = result
                activeJob?.stage = .signed
                activeJob?.detail = "Signed locally and verified. Ready to publish."
                progress = 1
                successMessage = "Signed locally. The signed IPA has not been uploaded yet."
            } catch {
                activeJob?.stage = .failed
                activeJob?.detail = error.localizedDescription
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    func publishSigned() {
        guard !isWorking else { return }
        guard let signed = signedResult else {
            errorMessage = "Sign the IPA locally first."
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

        persistConfiguration()
        isWorking = true
        progress = 0
        errorMessage = nil
        successMessage = nil
        activeJob?.stage = .uploading
        activeJob?.detail = "Uploading the already-signed IPA to Next Solution."

        let service = GitHubService(token: currentToken, configuration: configuration)
        Task {
            do {
                _ = try await service.publishSignedIPA(signed) { value in
                    await MainActor.run { self.progress = value }
                }
                activeJob?.stage = .published
                activeJob?.detail = "Published to nextsolution.cc/install/."
                successMessage = "Signed IPA published successfully. Registered devices can install it from the private app page."
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

        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextSignerInbox", isDirectory: true)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let sanitized = source.lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let destination = folder.appendingPathComponent(sanitized)
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
