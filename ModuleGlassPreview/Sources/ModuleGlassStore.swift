import Foundation
import SwiftUI
import UIKit
import CoreFoundation

@MainActor
final class ModuleGlassStore: ObservableObject {
    static let prefsDomain = "com.nextsolution.unlockvibrate" as CFString
    static let backgroundDirectory = "/var/mobile/Library/Preferences/NextSolutionTweaks/CCBackgrounds"
    static let tweakLogPath = "/var/mobile/Library/Logs/NextSolution/module-glass.log"
    static let consoleLogPath = "/var/mobile/Library/Logs/NextSolution/module-glass-preview.log"
    static let notificationNames = [
        "com.nextsolution.unlockvibrate/preferences.changed",
        "preferences.changed"
    ]

    @Published var enabled = true
    @Published var opacity = 1.0
    @Published var removeBlur = false
    @Published var volumeIconColorEnabled = false
    @Published var volumeIconColor = "#FFFFFF"
    @Published var deviceLive = true
    @Published var continuousApply = false

    @Published var selectedModuleID = "connectivity"
    @Published var simulatedBrightness = 0.72
    @Published var simulatedVolume = 0.58
    @Published var previewDim = 0.0
    @Published var previewScale = 1.0

    @Published var status = "Ready"
    @Published var events: [ConsoleEvent] = []
    @Published var imageRevision = UUID()
    @Published var diagnosticText = ""
    @Published var diagnosticJSON = ""
    @Published var diagnosticsRunning = false
    @Published var uploadRunning = false
    @Published var lastUploaded: UploadedDiagnostic?
    @Published var githubToken = KeychainTokenStore.load()

    var selectedModule: ModuleSlot { ModuleSlot.slot(selectedModuleID) }

    init() {
        ensureDirectories()
        loadPreferences(logEvent: false)
        record(.info, "Module Glass Developer Console 1.1.0 started")
    }

    // MARK: - Preferences

    func loadPreferences(logEvent: Bool = true) {
        CFPreferencesAppSynchronize(Self.prefsDomain)
        enabled = boolValue("CCModuleBackgroundsEnabled", fallback: true)
        opacity = min(1, max(0, doubleValue("CCModuleBackgroundOpacity", fallback: 1.0)))
        removeBlur = boolValue("CCModuleRemoveBlur", fallback: false)
        volumeIconColorEnabled = boolValue("CCModuleVolumeIconColorEnabled", fallback: false)
        volumeIconColor = normalizedHex(stringValue("CCModuleVolumeIconColor", fallback: "#FFFFFF"))
        imageRevision = UUID()
        status = "Device preferences loaded"
        if logEvent { record(.success, "Reloaded Stable Recovery preferences from \(Self.prefsDomain)") }
    }

    func applyPreferences(reason: String = "Manual apply") {
        guard deviceLive else {
            status = "Preview only — Device Live is off"
            record(.warning, "Skipped device apply because Device Live is off")
            return
        }

        let values: [(String, Any)] = [
            ("CCModuleBackgroundsEnabled", NSNumber(value: enabled)),
            ("CCModuleBackgroundOpacity", NSNumber(value: opacity)),
            ("CCModuleRemoveBlur", NSNumber(value: removeBlur)),
            ("CCModuleVolumeIconColorEnabled", NSNumber(value: volumeIconColorEnabled)),
            ("CCModuleVolumeIconColor", normalizedHex(volumeIconColor) as NSString)
        ]

        for (key, value) in values {
            CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, Self.prefsDomain)
        }
        let synced = CFPreferencesAppSynchronize(Self.prefsDomain)
        postReloadNotifications(logEvent: false)
        status = synced ? "Applied live to Module Glass" : "Preferences written; sync reported false"
        record(synced ? .success : .warning, "\(reason): enabled=\(enabled) opacity=\(String(format: "%.2f", opacity)) removeBlur=\(removeBlur) volumeColor=\(volumeIconColorEnabled ? normalizedHex(volumeIconColor) : "native")")
    }

    func applyIfContinuous(reason: String) {
        if continuousApply { applyPreferences(reason: reason) }
    }

    func postReloadNotifications(logEvent: Bool = true) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in Self.notificationNames {
            CFNotificationCenterPostNotification(
                center,
                CFNotificationName(rawValue: name as CFString),
                nil,
                nil,
                true
            )
        }
        status = "Reload notification sent"
        if logEvent { record(.success, "Posted Darwin reload notifications: \(Self.notificationNames.joined(separator: ", "))") }
    }

    // MARK: - Module images

    func imagePath(for moduleID: String) -> String {
        "\(Self.backgroundDirectory)/\(moduleID).jpg"
    }

    func image(for moduleID: String) -> UIImage? {
        UIImage(contentsOfFile: imagePath(for: moduleID))
    }

    func imageInfo(for slot: ModuleSlot) -> ModuleImageInfo {
        let path = imagePath(for: slot.id)
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let date = attrs?[.modificationDate] as? Date
        let uiImage = UIImage(contentsOfFile: path)
        let width = uiImage.flatMap { $0.cgImage?.width } ?? 0
        let height = uiImage.flatMap { $0.cgImage?.height } ?? 0
        return ModuleImageInfo(
            moduleID: slot.id,
            title: slot.title,
            path: path,
            exists: fm.fileExists(atPath: path),
            sizeBytes: size,
            width: width,
            height: height,
            modifiedAt: date,
            decodes: uiImage != nil
        )
    }

    func saveImage(_ image: UIImage, for slot: ModuleSlot) {
        guard deviceLive else {
            status = "Turn on Device Live before writing module images"
            record(.warning, "Image write blocked for \(slot.id): Device Live off")
            return
        }
        do {
            try FileManager.default.createDirectory(atPath: Self.backgroundDirectory, withIntermediateDirectories: true)
            guard let data = image.jpegData(compressionQuality: 0.95) else {
                throw NSError(domain: "ModuleGlassPreview", code: 20, userInfo: [NSLocalizedDescriptionKey: "JPEG encoding failed"])
            }
            let path = imagePath(for: slot.id)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            imageRevision = UUID()
            postReloadNotifications(logEvent: false)
            status = "\(slot.title) updated live"
            record(.success, "Wrote \(slot.id).jpg (\(data.count) bytes) to Stable Recovery image directory")
        } catch {
            status = "Image write failed: \(error.localizedDescription)"
            record(.error, "Image write failed for \(slot.id): \(error.localizedDescription)")
        }
    }

    func removeImage(for slot: ModuleSlot) {
        guard deviceLive else {
            status = "Turn on Device Live before removing module images"
            record(.warning, "Image removal blocked for \(slot.id): Device Live off")
            return
        }
        let path = imagePath(for: slot.id)
        do {
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
            imageRevision = UUID()
            postReloadNotifications(logEvent: false)
            status = "\(slot.title) image removed"
            record(.success, "Removed \(slot.id).jpg")
        } catch {
            status = "Remove failed: \(error.localizedDescription)"
            record(.error, "Remove failed for \(slot.id): \(error.localizedDescription)")
        }
    }

    // MARK: - Logging

    func record(_ level: ConsoleEvent.Level, _ message: String) {
        let event = ConsoleEvent(level: level, message: message)
        events.insert(event, at: 0)
        if events.count > 250 { events.removeLast(events.count - 250) }

        ensureDirectories()
        let formatter = ISO8601DateFormatter()
        let line = "[\(formatter.string(from: event.date))] [\(level.rawValue)] \(message)\n"
        let url = URL(fileURLWithPath: Self.consoleLogPath)
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    try? handle.close()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Diagnostics

    func runDiagnostics() async {
        diagnosticsRunning = true
        status = "Running diagnostics…"
        record(.info, "Deep diagnostics started")

        let images = ModuleSlot.all.map(imageInfo(for:))
        let writable = testBackgroundDirectoryWrite()
        let packageEvidence = installedPackageEvidence()
        let report = DiagnosticReport(
            generatedAt: Date(),
            device: DiagnosticReport.Device(
                model: UIDevice.current.model,
                systemName: UIDevice.current.systemName,
                systemVersion: UIDevice.current.systemVersion,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                bundleID: Bundle.main.bundleIdentifier ?? "unknown"
            ),
            preferences: DiagnosticReport.Preferences(
                domain: Self.prefsDomain as String,
                enabled: enabled,
                opacity: opacity,
                removeBlur: removeBlur,
                volumeIconColorEnabled: volumeIconColorEnabled,
                volumeIconColor: normalizedHex(volumeIconColor)
            ),
            paths: DiagnosticReport.Paths(
                imageDirectory: Self.backgroundDirectory,
                tweakLog: Self.tweakLogPath,
                consoleLog: Self.consoleLogPath,
                imageDirectoryWritable: writable
            ),
            images: images,
            packages: packageEvidence,
            notifications: Self.notificationNames,
            events: Array(events.prefix(100)),
            tweakLogTail: tailText(path: Self.tweakLogPath, maxBytes: 80_000),
            consoleLogTail: tailText(path: Self.consoleLogPath, maxBytes: 80_000)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = (try? encoder.encode(report)) ?? Data("{}".utf8)
        diagnosticJSON = String(data: jsonData, encoding: .utf8) ?? "{}"
        diagnosticText = textReport(report)
        diagnosticsRunning = false
        status = "Diagnostics ready"
        record(.success, "Diagnostics completed: \(images.filter(\.exists).count)/\(images.count) module images present; image directory writable=\(writable)")
    }

    func saveGitHubToken() {
        if KeychainTokenStore.save(githubToken) {
            status = githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "GitHub token removed" : "GitHub token saved in Keychain"
            record(.success, status)
        } else {
            status = "Could not save GitHub token"
            record(.error, status)
        }
    }

    func clearGitHubToken() {
        githubToken = ""
        _ = KeychainTokenStore.delete()
        status = "GitHub token removed from Keychain"
        record(.success, status)
    }

    func uploadDiagnostics() async {
        if diagnosticText.isEmpty || diagnosticJSON.isEmpty {
            await runDiagnostics()
        }
        let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            status = "Enter a GitHub PAT first"
            record(.warning, "Diagnostic upload requested without a GitHub PAT")
            return
        }

        uploadRunning = true
        status = "Uploading diagnostics…"
        let stamp = uploadTimestamp()
        let base = "transfer/uploads/moduleglass/\(stamp)-ModuleGlassPreview"
        let textPath = "\(base).log"
        let jsonPath = "\(base).json"
        let uploader = GitHubLogUploader()

        do {
            try await uploader.upload(
                path: textPath,
                data: Data(diagnosticText.utf8),
                token: token,
                commitMessage: "Upload Module Glass diagnostic log \(stamp)"
            )
            try await uploader.upload(
                path: jsonPath,
                data: Data(diagnosticJSON.utf8),
                token: token,
                commitMessage: "Upload Module Glass diagnostic JSON \(stamp)"
            )
            lastUploaded = UploadedDiagnostic(textPath: textPath, jsonPath: jsonPath)
            status = "Diagnostic log uploaded"
            record(.success, "Uploaded diagnostic files to \(textPath) and \(jsonPath). Token was not logged.")
        } catch {
            status = "Upload failed: \(error.localizedDescription)"
            record(.error, "Diagnostic upload failed: \(error.localizedDescription)")
        }
        uploadRunning = false
    }

    // MARK: - Helpers

    private func boolValue(_ key: String, fallback: Bool) -> Bool {
        guard let raw = CFPreferencesCopyAppValue(key as CFString, Self.prefsDomain) else { return fallback }
        return (raw as? NSNumber)?.boolValue ?? fallback
    }

    private func doubleValue(_ key: String, fallback: Double) -> Double {
        guard let raw = CFPreferencesCopyAppValue(key as CFString, Self.prefsDomain) else { return fallback }
        return (raw as? NSNumber)?.doubleValue ?? fallback
    }

    private func stringValue(_ key: String, fallback: String) -> String {
        guard let raw = CFPreferencesCopyAppValue(key as CFString, Self.prefsDomain) else { return fallback }
        return (raw as? String) ?? fallback
    }

    func normalizedHex(_ input: String) -> String {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let body = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEF")
        let filtered = String(body.unicodeScalars.filter { allowed.contains($0) })
        if filtered.count == 6 || filtered.count == 8 { return "#\(filtered)" }
        return "#FFFFFF"
    }

    private func ensureDirectories() {
        try? FileManager.default.createDirectory(atPath: Self.backgroundDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: (Self.consoleLogPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    }

    private func testBackgroundDirectoryWrite() -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: Self.backgroundDirectory, withIntermediateDirectories: true)
            let path = "\(Self.backgroundDirectory)/.mgpreview-write-test-\(UUID().uuidString)"
            try Data("test".utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            record(.error, "Background directory write test failed: \(error.localizedDescription)")
            return false
        }
    }

    private func tailText(path: String, maxBytes: Int) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "<file not found>" }
        let clipped = data.count > maxBytes ? data.suffix(maxBytes) : data[...]
        return String(data: Data(clipped), encoding: .utf8) ?? "<not UTF-8: \(data.count) bytes>"
    }

    private func installedPackageEvidence() -> [PackageEvidence] {
        let statusPaths = [
            "/var/jb/Library/dpkg/status",
            "/var/jb/var/lib/dpkg/status",
            "/var/lib/dpkg/status",
            "/Library/dpkg/status"
        ]
        let packages = [
            "com.nextsolution.nextaura.cc-module-backgrounds",
            "com.nextsolution.nextaura.runtime.ccbackgrounds",
            "com.nextsolution.nextaura.runtime.preferences"
        ]

        guard let statusPath = statusPaths.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let text = try? String(contentsOfFile: statusPath, encoding: .utf8) else {
            return packages.map { PackageEvidence(statusPath: "<dpkg status not found in known paths>", package: $0, version: nil, installed: false) }
        }

        let paragraphs = text.components(separatedBy: "\n\n")
        return packages.map { package in
            guard let block = paragraphs.first(where: { $0.contains("Package: \(package)") }) else {
                return PackageEvidence(statusPath: statusPath, package: package, version: nil, installed: false)
            }
            let versionLine = block.split(separator: "\n").first(where: { $0.hasPrefix("Version:") })
            let version = versionLine.map { $0.replacingOccurrences(of: "Version:", with: "").trimmingCharacters(in: .whitespaces) }
            let installed = block.contains("Status: install ok installed") || !block.contains("Status:")
            return PackageEvidence(statusPath: statusPath, package: package, version: version, installed: installed)
        }
    }

    private func textReport(_ report: DiagnosticReport) -> String {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("MODULE GLASS DEVELOPER CONSOLE DIAGNOSTIC")
        lines.append("Generated: \(formatter.string(from: report.generatedAt))")
        lines.append("App: \(report.device.appVersion) (\(report.device.appBuild)) / \(report.device.bundleID)")
        lines.append("Device: \(report.device.model) / \(report.device.systemName) \(report.device.systemVersion)")
        lines.append("")
        lines.append("PREFERENCES")
        lines.append("Domain: \(report.preferences.domain)")
        lines.append("Enabled: \(report.preferences.enabled)")
        lines.append("Opacity: \(String(format: "%.3f", report.preferences.opacity))")
        lines.append("Remove Blur: \(report.preferences.removeBlur)")
        lines.append("Volume icon color enabled: \(report.preferences.volumeIconColorEnabled)")
        lines.append("Volume icon color: \(report.preferences.volumeIconColor)")
        lines.append("")
        lines.append("PATHS")
        lines.append("Images: \(report.paths.imageDirectory)")
        lines.append("Images writable: \(report.paths.imageDirectoryWritable)")
        lines.append("Tweak log: \(report.paths.tweakLog)")
        lines.append("Console log: \(report.paths.consoleLog)")
        lines.append("")
        lines.append("MODULE IMAGES")
        for info in report.images {
            lines.append("\(info.moduleID): exists=\(info.exists) decode=\(info.decodes) bytes=\(info.sizeBytes) pixels=\(info.width)x\(info.height) path=\(info.path)")
        }
        lines.append("")
        lines.append("PACKAGE EVIDENCE")
        for item in report.packages {
            lines.append("\(item.package): installed=\(item.installed) version=\(item.version ?? "unknown") status=\(item.statusPath)")
        }
        lines.append("")
        lines.append("DARWIN NOTIFICATIONS")
        lines.append(contentsOf: report.notifications)
        lines.append("")
        lines.append("RECENT CONSOLE EVENTS")
        for event in report.events {
            lines.append("[\(formatter.string(from: event.date))] [\(event.level.rawValue)] \(event.message)")
        }
        lines.append("")
        lines.append("TWEAK LOG TAIL")
        lines.append(report.tweakLogTail)
        lines.append("")
        lines.append("CONSOLE LOG TAIL")
        lines.append(report.consoleLogTail)
        return lines.joined(separator: "\n")
    }

    private func uploadTimestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
