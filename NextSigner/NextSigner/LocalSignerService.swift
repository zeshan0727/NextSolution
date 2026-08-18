import Foundation
import ZIPFoundation
import ProStoreTools

struct SignedAppResult: Equatable {
    let ipaURL: URL
    let appName: String
    let bundleID: String
    let version: String
    let build: String
    let minimumOS: String
}

enum LocalSignerError: LocalizedError {
    case missingCertificate
    case missingProvisioningProfile
    case missingPassword
    case invalidIPA
    case appBundleMissing
    case infoPlistMissing
    case signingFailed(String)
    case signedOutputInvalid

    var errorDescription: String? {
        switch self {
        case .missingCertificate:
            return "Import a .p12 signing certificate in Settings first."
        case .missingProvisioningProfile:
            return "Import a .mobileprovision profile in Settings first."
        case .missingPassword:
            return "Enter and save the P12 password in Settings first."
        case .invalidIPA:
            return "The selected file could not be extracted as an IPA."
        case .appBundleMissing:
            return "No application bundle was found inside Payload."
        case .infoPlistMissing:
            return "The app Info.plist could not be read."
        case let .signingFailed(message):
            return "Local signing failed: \(message)"
        case .signedOutputInvalid:
            return "Signing finished, but the resulting IPA did not contain the expected code-signature and provisioning files."
        }
    }
}

struct LocalSignerService {
    func sign(
        ipaURL: URL,
        requestedName: String,
        requestedBundleID: String,
        p12URL: URL,
        provisioningURL: URL,
        p12Password: String
    ) async throws -> SignedAppResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: p12URL.path) else {
            throw LocalSignerError.missingCertificate
        }
        guard fm.fileExists(atPath: provisioningURL.path) else {
            throw LocalSignerError.missingProvisioningProfile
        }
        guard !p12Password.isEmpty else {
            throw LocalSignerError.missingPassword
        }

        let cleanName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBundleID = requestedBundleID.trimmingCharacters(in: .whitespacesAndNewlines)

        let preparationRoot = fm.temporaryDirectory
            .appendingPathComponent("NextSignerPrepare-\(UUID().uuidString)", isDirectory: true)
        let unpacked = preparationRoot.appendingPathComponent("unpacked", isDirectory: true)
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: preparationRoot) }

        do {
            try fm.unzipItem(at: ipaURL, to: unpacked)
        } catch {
            throw LocalSignerError.invalidIPA
        }

        let appURL = try findMainApp(in: unpacked)
        let originalBundleID = try updateMainAppMetadata(
            appURL: appURL,
            appName: cleanName,
            bundleID: cleanBundleID
        )
        try updateExtensionBundleIdentifiers(
            in: appURL,
            originalMainBundleID: originalBundleID,
            newMainBundleID: cleanBundleID
        )

        let preparedIPA = preparationRoot.appendingPathComponent("prepared.ipa")
        do {
            try fm.zipItem(
                at: unpacked,
                to: preparedIPA,
                shouldKeepParent: false,
                compressionMethod: .deflate
            )
        } catch {
            throw LocalSignerError.invalidIPA
        }

        let producedURL: URL
        do {
            producedURL = try await withCheckedThrowingContinuation { continuation in
                ProStoreTools.sign(
                    ipaURL: preparedIPA,
                    p12URL: p12URL,
                    provURL: provisioningURL,
                    p12Password: p12Password,
                    progressUpdate: { _ in },
                    completion: { result in
                        continuation.resume(with: result)
                    }
                )
            }
        } catch {
            throw LocalSignerError.signingFailed(error.localizedDescription)
        }

        let verified = try inspectSignedIPA(producedURL)
        guard verified.bundleID == cleanBundleID,
              verified.hasCodeResources,
              verified.hasProvisioningProfile else {
            throw LocalSignerError.signedOutputInvalid
        }

        let signedDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextSigner Signed", isDirectory: true)
        try fm.createDirectory(at: signedDirectory, withIntermediateDirectories: true)

        let outputURL = signedDirectory.appendingPathComponent(
            "\(safeFilename(verified.appName))-\(safeFilename(verified.version))-signed-\(Int(Date().timeIntervalSince1970)).ipa"
        )
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }
        try fm.copyItem(at: producedURL, to: outputURL)
        try? fm.removeItem(at: producedURL)

        return SignedAppResult(
            ipaURL: outputURL,
            appName: verified.appName,
            bundleID: verified.bundleID,
            version: verified.version,
            build: verified.build,
            minimumOS: verified.minimumOS
        )
    }

    private func findMainApp(in root: URL) throws -> URL {
        let payload = root.appendingPathComponent("Payload", isDirectory: true)
        guard let app = try? FileManager.default.contentsOfDirectory(
            at: payload,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).first(where: { $0.pathExtension.lowercased() == "app" }) else {
            throw LocalSignerError.appBundleMissing
        }
        return app
    }

    @discardableResult
    private func updateMainAppMetadata(appURL: URL, appName: String, bundleID: String) throws -> String {
        let plistURL = appURL.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw LocalSignerError.infoPlistMissing
        }

        let originalBundleID = (plist["CFBundleIdentifier"] as? String) ?? ""
        plist["CFBundleIdentifier"] = bundleID
        if !appName.isEmpty {
            plist["CFBundleDisplayName"] = appName
            plist["CFBundleName"] = appName
        }
        let updated = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try updated.write(to: plistURL, options: .atomic)
        return originalBundleID
    }

    private func updateExtensionBundleIdentifiers(
        in appURL: URL,
        originalMainBundleID: String,
        newMainBundleID: String
    ) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: appURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var fallbackIndex = 0
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "appex" {
            enumerator.skipDescendants()
            let plistURL = url.appendingPathComponent("Info.plist")
            guard let data = try? Data(contentsOf: plistURL),
                  var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                continue
            }

            let oldExtensionID = (plist["CFBundleIdentifier"] as? String) ?? ""
            let newExtensionID: String
            if !originalMainBundleID.isEmpty,
               oldExtensionID.hasPrefix(originalMainBundleID + ".") {
                newExtensionID = newMainBundleID + oldExtensionID.dropFirst(originalMainBundleID.count)
            } else {
                fallbackIndex += 1
                newExtensionID = "\(newMainBundleID).extension\(fallbackIndex)"
            }
            plist["CFBundleIdentifier"] = newExtensionID

            if let companion = plist["WKCompanionAppBundleIdentifier"] as? String,
               companion == originalMainBundleID {
                plist["WKCompanionAppBundleIdentifier"] = newMainBundleID
            }

            let updated = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            try updated.write(to: plistURL, options: .atomic)
        }
    }

    private func inspectSignedIPA(_ ipaURL: URL) throws -> SignedInspection {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("NextSignerVerify-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        do {
            try fm.unzipItem(at: ipaURL, to: root)
        } catch {
            throw LocalSignerError.signedOutputInvalid
        }

        let appURL = try findMainApp(in: root)
        let plistURL = appURL.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw LocalSignerError.infoPlistMissing
        }

        let appName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? "Signed App"
        let bundleID = (plist["CFBundleIdentifier"] as? String) ?? ""
        let version = (plist["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = (plist["CFBundleVersion"] as? String) ?? "1"
        let minimumOS = (plist["MinimumOSVersion"] as? String) ?? "iOS"

        let codeResources = appURL
            .appendingPathComponent("_CodeSignature", isDirectory: true)
            .appendingPathComponent("CodeResources")
        let embeddedProfile = appURL.appendingPathComponent("embedded.mobileprovision")

        return SignedInspection(
            appName: appName,
            bundleID: bundleID,
            version: version,
            build: build,
            minimumOS: minimumOS,
            hasCodeResources: fm.fileExists(atPath: codeResources.path),
            hasProvisioningProfile: fm.fileExists(atPath: embeddedProfile.path)
        )
    }

    private func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let chars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        var result = String(chars)
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "Signed-App" : result
    }

    private struct SignedInspection {
        let appName: String
        let bundleID: String
        let version: String
        let build: String
        let minimumOS: String
        let hasCodeResources: Bool
        let hasProvisioningProfile: Bool
    }
}
