import Foundation

struct SignRequest: Equatable {
    var ipaURL: URL?
    var appName: String = ""
    var bundleID: String = ""

    var isReady: Bool {
        ipaURL != nil && !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isValidBundleID
    }

    var isValidBundleID: Bool {
        let value = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 3, value.contains("."), !value.hasPrefix("."), !value.hasSuffix(".") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

struct GitHubConfiguration: Equatable {
    var owner: String = "zeshan0727"
    var repository: String = "NextSolution"
    var branch: String = "main"

    var isValid: Bool {
        !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SigningJob: Identifiable, Equatable {
    let id = UUID()
    let sourceName: String
    let requestedBundleID: String
    let requestedAppName: String
    var stage: Stage
    var detail: String

    enum Stage: String {
        case preparing = "Preparing"
        case signing = "Signing"
        case signed = "Signed"
        case uploading = "Uploading"
        case published = "Published"
        case failed = "Failed"
    }
}

enum NextSignerError: LocalizedError {
    case missingToken
    case invalidConfiguration
    case invalidResponse
    case http(Int, String)
    case uploadFailed
    case malformedURL

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "GitHub access token is not configured."
        case .invalidConfiguration:
            return "GitHub repository settings are incomplete."
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case let .http(code, message):
            if code == 403 {
                return "GitHub error 403: \(message). Use a fine-grained token that has access to the NextSolution repository with Contents set to Read and write."
            }
            return "GitHub error \(code): \(message)"
        case .uploadFailed:
            return "The signed IPA could not be uploaded."
        case .malformedURL:
            return "A GitHub API URL could not be created."
        }
    }
}
