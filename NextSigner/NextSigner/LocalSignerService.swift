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
            return "The app was processed, but the resulting executable did not verify as signed."
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
    ) throws -> SignedAppResult {
        guard FileManager.default.fileExists(atPath: p12URL.path) else {
            throw LocalSignerError.missingCertificate
        }
        guard FileManager.default.fileExists(atPath: provisioningURL.path) else {
            throw LocalSignerError.missingProvisioningProfile
        }
        guard !p12Password.isEmpty else {
            throw LocalSignerError.missingPassword
        }

        let fm = FileManager.default
        let workRoot = fm.temporaryDirectory
            .appendingPathComponent("NextSigner-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workRoot) }

        do {
            try fm.unzipItem(at: ipaURL, to: workRoot)
        } catch {
            throw LocalSignerError.invalidIPA
        }

        let payload = workRoot.appendingPathComponent("Payload", isDirectory: true)
        guard let appURL = try fm.contentsOfDirectory(
            at: payload,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).first(where: { $0.pathExtension.lowercased() == "app" }) else {
            throw LocalSignerError.appBundleMissing
        }

        let plistURL = appURL.appendingPathComponent("Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              var plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw LocalSignerError.infoPlistMissing
        }

        let cleanName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBundleID = requestedBundleID.trimmingCharacters(in: .whitespacesAndNewlines)

        let ok = Zsign.sign(
            appPath: appURL.path,
            provisionPath: provisioningURL.path,
            p12Path: p12URL.path,
            p12Password: p12Password,
            customIdentifier: cleanBundleID,
            customName: cleanName,
            adhoc: false,
            removeProvision: false
        )
        guard ok else { throw LocalSignerError.signingFailed }

        guard let updatedData = try? Data(contentsOf: plistURL),
              let updatedPlist = try? PropertyListSerialization.propertyList(from: updatedData, format: nil) as? [String: Any] else {
            throw LocalSignerError.infoPlistMissing
        }
        plist = updatedPlist

        let executableName = (plist["CFBundleExecutable"] as? String) ?? ""
        let executableURL = appURL.appendingPathComponent(executableName)
        if !executableName.isEmpty,
           fm.fileExists(atPath: executableURL.path),
           !Zsign.checkSigned(appExecutable: executableURL.path) {
            throw LocalSignerError.signatureVerificationFailed
        }

        let version = (plist["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = (plist["CFBundleVersion"] as? String) ?? "1"
        let minimumOS = (plist["MinimumOSVersion"] as? String) ?? "iOS"
        let finalBundleID = (plist["CFBundleIdentifier"] as? String) ?? cleanBundleID
        let finalName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? cleanName

        let signedDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextSigner Signed", isDirectory: true)
        try fm.createDirectory(at: signedDirectory, withIntermediateDirectories: true)

        let slug = safeFilename(finalName)
        let outputURL = signedDirectory.appendingPathComponent(
            "\(slug)-\(version)-signed-\(Int(Date().timeIntervalSince1970)).ipa"
        )
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        try fm.zipItem(
            at: workRoot,
            to: outputURL,
            shouldKeepParent: false,
            compressionMethod: .deflate
        )

        return SignedAppResult(
            ipaURL: outputURL,
            appName: finalName,
            bundleID: finalBundleID,
            version: version,
            build: build,
            minimumOS: minimumOS
        )
    }

    private func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let chars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(chars).replacingOccurrences(of: "--", with: "-")
        return result.isEmpty ? "Signed-App" : result
    }
}
