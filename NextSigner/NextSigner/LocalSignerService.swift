import Foundation
import ZIPFoundation
import Zsign

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
    case signingFailed
    case signatureVerificationFailed

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
        case .signingFailed:
            return "Local Zsign signing failed. Check the certificate password, provisioning profile and bundle identifier."
        case .signatureVerificationFailed:
            return "Signing completed, but the resulting executable did not verify as signed."
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
        try await Task.detached(priority: .userInitiated) {
            try signSynchronously(
                ipaURL: ipaURL,
                requestedName: requestedName,
                requestedBundleID: requestedBundleID,
                p12URL: p12URL,
                provisioningURL: provisioningURL,
                p12Password: p12Password
            )
        }.value
    }

    private func signSynchronously(
        ipaURL: URL,
        requestedName: String,
        requestedBundleID: String,
        p12URL: URL,
        provisioningURL: URL,
        p12Password: String
    ) throws -> SignedAppResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: p12URL.path) else { throw LocalSignerError.missingCertificate }
        guard fm.fileExists(atPath: provisioningURL.path) else { throw LocalSignerError.missingProvisioningProfile }
        guard !p12Password.isEmpty else { throw LocalSignerError.missingPassword }

        let cleanName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBundleID = requestedBundleID.trimmingCharacters(in: .whitespacesAndNewlines)

        let workRoot = fm.temporaryDirectory.appendingPathComponent("NextSigner-\(UUID().uuidString)", isDirectory: true)
        let unpacked = workRoot.appendingPathComponent("unpacked", isDirectory: true)
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workRoot) }

        do {
            try fm.unzipItem(at: ipaURL, to: unpacked)
        } catch {
            throw LocalSignerError.invalidIPA
        }

        let appURL = try findMainApp(in: unpacked)
        let originalBundleID = try updateMainAppMetadata(appURL: appURL, appName: cleanName, bundleID: cleanBundleID)
        try updateExtensionBundleIdentifiers(in: appURL, originalMainBundleID: originalBundleID, newMainBundleID: cleanBundleID)

        let signedOK = Zsign.sign(
            appPath: appURL.path,
            provisionPath: provisioningURL.path,
            p12Path: p12URL.path,
            p12Password: p12Password,
            entitlementsPath: "",
            customIdentifier: cleanBundleID,
            customName: cleanName,
            customVersion: "",
            adhoc: false,
            removeProvision: false
        )
        guard signedOK else { throw LocalSignerError.signingFailed }

        let plistURL = appURL.appendingPathComponent("Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw LocalSignerError.infoPlistMissing
        }

        let executableName = (plist["CFBundleExecutable"] as? String) ?? ""
        let executableURL = appURL.appendingPathComponent(executableName)
        if !executableName.isEmpty,
           fm.fileExists(atPath: executableURL.path),
           !Zsign.checkSigned(appExecutable: executableURL.path) {
            throw LocalSignerError.signatureVerificationFailed
        }

        let finalName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? cleanName
        let finalBundleID = (plist["CFBundleIdentifier"] as? String) ?? cleanBundleID
        let version = (plist["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = (plist["CFBundleVersion"] as? String) ?? "1"
        let minimumOS = (plist["MinimumOSVersion"] as? String) ?? "iOS"

        let codeResources = appURL.appendingPathComponent("_CodeSignature", isDirectory: true).appendingPathComponent("CodeResources")
        let embeddedProfile = appURL.appendingPathComponent("embedded.mobileprovision")
        guard fm.fileExists(atPath: codeResources.path), fm.fileExists(atPath: embeddedProfile.path) else {
            throw LocalSignerError.signatureVerificationFailed
        }

        let signedDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextSigner Signed", isDirectory: true)
        try fm.createDirectory(at: signedDirectory, withIntermediateDirectories: true)

        let outputURL = signedDirectory.appendingPathComponent(
            "\(safeFilename(finalName))-\(safeFilename(version))-signed-\(Int(Date().timeIntervalSince1970)).ipa"
        )
        if fm.fileExists(atPath: outputURL.path) { try fm.removeItem(at: outputURL) }

        do {
            try fm.zipItem(at: unpacked, to: outputURL, shouldKeepParent: false, compressionMethod: .deflate)
        } catch {
            throw LocalSignerError.invalidIPA
        }

        return SignedAppResult(
            ipaURL: outputURL,
            appName: finalName,
            bundleID: finalBundleID,
            version: version,
            build: build,
            minimumOS: minimumOS
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

    private func updateExtensionBundleIdentifiers(in appURL: URL, originalMainBundleID: String, newMainBundleID: String) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: appURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }

        var fallbackIndex = 0
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "appex" {
            enumerator.skipDescendants()
            let plistURL = url.appendingPathComponent("Info.plist")
            guard let data = try? Data(contentsOf: plistURL),
                  var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }

            let oldExtensionID = (plist["CFBundleIdentifier"] as? String) ?? ""
            if !originalMainBundleID.isEmpty, oldExtensionID.hasPrefix(originalMainBundleID + ".") {
                plist["CFBundleIdentifier"] = newMainBundleID + oldExtensionID.dropFirst(originalMainBundleID.count)
            } else {
                fallbackIndex += 1
                plist["CFBundleIdentifier"] = "\(newMainBundleID).extension\(fallbackIndex)"
            }
            if let companion = plist["WKCompanionAppBundleIdentifier"] as? String, companion == originalMainBundleID {
                plist["WKCompanionAppBundleIdentifier"] = newMainBundleID
            }
            let updated = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            try updated.write(to: plistURL, options: .atomic)
        }
    }

    private func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let chars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(chars).replacingOccurrences(of: "--", with: "-")
        return result.isEmpty ? "Signed-App" : result
    }
}
