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
            return "Signing completed, but the main executable did not contain an embedded code-signature command."
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
        let finalName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? cleanName
        let finalBundleID = (plist["CFBundleIdentifier"] as? String) ?? cleanBundleID
        let version = (plist["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = (plist["CFBundleVersion"] as? String) ?? "1"
        let minimumOS = (plist["MinimumOSVersion"] as? String) ?? "iOS"

        let embeddedProfile = appURL.appendingPathComponent("embedded.mobileprovision")
        guard !executableName.isEmpty,
              fm.fileExists(atPath: executableURL.path),
              fileHasContent(executableURL),
              fm.fileExists(atPath: embeddedProfile.path),
              fileHasContent(embeddedProfile),
              finalBundleID == cleanBundleID,
              executableContainsCodeSignature(executableURL) else {
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

    private func fileHasContent(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return false }
        return size > 0
    }

    private func executableContainsCodeSignature(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 4096), header.count >= 32 else { return false }

        func u32LE(_ data: Data, _ offset: Int) -> UInt32? {
            guard offset >= 0, offset + 4 <= data.count else { return nil }
            return data.withUnsafeBytes { raw in
                UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
        }

        func u32BE(_ data: Data, _ offset: Int) -> UInt32? {
            guard offset >= 0, offset + 4 <= data.count else { return nil }
            return data.withUnsafeBytes { raw in
                UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
        }

        func u64BE(_ data: Data, _ offset: Int) -> UInt64? {
            guard offset >= 0, offset + 8 <= data.count else { return nil }
            return data.withUnsafeBytes { raw in
                UInt64(bigEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
            }
        }

        func thinSliceHasSignature(at fileOffset: UInt64) -> Bool {
            do {
                try handle.seek(toOffset: fileOffset)
                guard let thinHeader = try handle.read(upToCount: 32), thinHeader.count >= 28,
                      let magic = u32LE(thinHeader, 0) else { return false }

                let is64: Bool
                switch magic {
                case 0xfeedfacf: is64 = true
                case 0xfeedface: is64 = false
                default: return false
                }

                let headerSize = is64 ? 32 : 28
                guard let ncmds = u32LE(thinHeader, 16) else { return false }
                try handle.seek(toOffset: fileOffset + UInt64(headerSize))

                for _ in 0..<min(ncmds, 4096) {
                    guard let cmdHeader = try handle.read(upToCount: 8), cmdHeader.count == 8,
                          let cmd = u32LE(cmdHeader, 0),
                          let cmdSize = u32LE(cmdHeader, 4),
                          cmdSize >= 8 else { return false }

                    if cmd == 0x1d { return true }
                    if cmdSize > 8 {
                        try handle.seek(toOffset: handle.offsetInFile + UInt64(cmdSize - 8))
                    }
                }
                return false
            } catch {
                return false
            }
        }

        if let thinMagic = u32LE(header, 0), thinMagic == 0xfeedfacf || thinMagic == 0xfeedface {
            return thinSliceHasSignature(at: 0)
        }

        guard let fatMagic = u32BE(header, 0),
              fatMagic == 0xcafebabe || fatMagic == 0xcafebabf,
              let sliceCount = u32BE(header, 4) else { return false }

        let isFat64 = fatMagic == 0xcafebabf
        let archSize = isFat64 ? 32 : 20
        var archOffset = 8

        for _ in 0..<min(sliceCount, 128) {
            let sliceOffset: UInt64?
            if isFat64 {
                sliceOffset = u64BE(header, archOffset + 8)
            } else if let value = u32BE(header, archOffset + 8) {
                sliceOffset = UInt64(value)
            } else {
                sliceOffset = nil
            }

            if let sliceOffset, thinSliceHasSignature(at: sliceOffset) { return true }
            archOffset += archSize
            if archOffset + archSize > header.count { break }
        }
        return false
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
