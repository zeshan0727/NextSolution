import Foundation
import SwiftUI
import UIKit
import CoreFoundation

enum ModuleAutoTestState: String, Codable, CaseIterable {
    case pass = "PASS"
    case native = "NATIVE"
    case notObserved = "NOT OBSERVED"
    case warning = "WARNING"
    case fail = "FAIL"

    var systemImage: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .native: return "circle.dotted"
        case .notObserved: return "eye.slash.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .pass: return .green
        case .native: return .secondary
        case .notObserved: return .orange
        case .warning: return .orange
        case .fail: return .red
        }
    }
}

struct ModuleAutoTestResult: Identifiable, Codable, Hashable {
    var id: String { moduleID }
    let moduleID: String
    let title: String
    let state: ModuleAutoTestState
    let reason: String
    let imageExists: Bool
    let imageDecodes: Bool
    let imageBytes: Int64
    let imageWidth: Int
    let imageHeight: Int
    let runtimeObserved: Bool
    let runtimeStrategy: String?
    let runtimeLine: String?
}

struct ModuleAutoTestReport: Codable {
    struct Summary: Codable {
        let pass: Int
        let native: Int
        let notObserved: Int
        let warning: Int
        let fail: Int
        let controllersSeen: Int
        let runtimeLines: Int
    }

    let sessionID: String
    let generatedAt: Date
    let appVersion: String
    let iOSVersion: String
    let deviceModel: String
    let preferenceDomain: String
    let runtimeLogPath: String
    let nextLogControlPath: String
    let summary: Summary
    let modules: [ModuleAutoTestResult]
    let runtimeLogDelta: String
    let deepDiagnosticText: String
    let consoleEvents: [ConsoleEvent]
}

@MainActor
final class ModuleGlassAutoTester: ObservableObject {
    static let nextLogControlPath = "/var/mobile/Library/Preferences/com.nextsolution.nextlog.plist"
    static let outputDirectory = "/var/mobile/Library/Logs/NextSolution/ModuleGlassAutoTests"

    @Published var running = false
    @Published var progress = 0.0
    @Published var phase = "Ready"
    @Published var results: [ModuleAutoTestResult] = []
    @Published var reportText = ""
    @Published var reportJSON = ""
    @Published var localLogPath: String?
    @Published var localJSONPath: String?
    @Published var autoUploadWhenTokenAvailable = true
    @Published var uploadedTextPath: String?
    @Published var uploadedJSONPath: String?
    @Published var controllersSeen = 0
    @Published var runtimeLinesCaptured = 0
    @Published var controlCenterNeeded = false

    func run(store: ModuleGlassStore) async {
        guard !running else { return }
        running = true
        progress = 0
        phase = "Preparing automatic test"
        results = []
        reportText = ""
        reportJSON = ""
        localLogPath = nil
        localJSONPath = nil
        uploadedTextPath = nil
        uploadedJSONPath = nil
        controllersSeen = 0
        runtimeLinesCaptured = 0
        controlCenterNeeded = false

        let sessionID = Self.sessionStamp()
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Self.outputDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: (Self.nextLogControlPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)

        let originalNextLogData = try? Data(contentsOf: URL(fileURLWithPath: Self.nextLogControlPath))
        let baselineOffset = fileSize(ModuleGlassStore.tweakLogPath)

        store.record(.info, "AUTO-TEST \(sessionID) started; runtime log baseline=\(baselineOffset) bytes")

        do {
            try enableRuntimeDiagnostics()
            store.record(.success, "AUTO-TEST enabled Module Glass verbose runtime diagnostics")
        } catch {
            store.record(.error, "AUTO-TEST could not enable Next Log control: \(error.localizedDescription)")
        }

        phase = "Triggering Module Glass runtime"
        progress = 0.08
        postDarwin("com.nextsolution.nextlog/control.changed")
        store.postReloadNotifications(logEvent: false)
        try? await Task.sleep(nanoseconds: 900_000_000)

        var delta = runtimeDelta(from: baselineOffset)
        var observedSlots = observedModuleIDs(in: delta)
        controllersSeen = maxControllers(in: delta)

        if observedSlots.isEmpty {
            controlCenterNeeded = true
            phase = "Open Control Center once, keep it open 2–3 seconds, then return"
            store.record(.warning, "AUTO-TEST waiting for Control Center because no module controller diagnostics were observed yet")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)

            for attempt in 1...30 {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
                if attempt % 4 == 0 {
                    postDarwin("com.nextsolution.nextlog/control.changed")
                }
                delta = runtimeDelta(from: baselineOffset)
                observedSlots = observedModuleIDs(in: delta)
                controllersSeen = max(controllersSeen, maxControllers(in: delta))
                progress = min(0.30, 0.08 + Double(attempt) * 0.007)
                if !observedSlots.isEmpty { break }
            }
        }

        controlCenterNeeded = false
        phase = "Capturing clean runtime refresh"
        postDarwin("com.nextsolution.nextlog/control.changed")
        try? await Task.sleep(nanoseconds: 850_000_000)
        delta = runtimeDelta(from: baselineOffset)
        controllersSeen = max(controllersSeen, maxControllers(in: delta))
        runtimeLinesCaptured = delta.split(separator: "\n", omittingEmptySubsequences: true).count

        let lines = delta.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var moduleResults: [ModuleAutoTestResult] = []

        for (index, slot) in ModuleSlot.all.enumerated() {
            phase = "Testing \(slot.title) (\(index + 1)/\(ModuleSlot.all.count))"
            progress = 0.32 + (Double(index) / Double(max(1, ModuleSlot.all.count))) * 0.46
            let info = store.imageInfo(for: slot)
            let relevant = lines.filter { $0.contains("slot=\(slot.id)") }
            let latest = relevant.last
            let result = evaluate(slot: slot, image: info, runtimeLine: latest)
            moduleResults.append(result)
            store.record(logLevel(for: result.state), "AUTO-TEST \(slot.id): \(result.state.rawValue) — \(result.reason)")
            try? await Task.sleep(nanoseconds: 35_000_000)
        }

        results = moduleResults
        phase = "Collecting deep device diagnostics"
        progress = 0.82
        await store.runDiagnostics()

        phase = "Building session report"
        progress = 0.90
        let summary = ModuleAutoTestReport.Summary(
            pass: moduleResults.filter { $0.state == .pass }.count,
            native: moduleResults.filter { $0.state == .native }.count,
            notObserved: moduleResults.filter { $0.state == .notObserved }.count,
            warning: moduleResults.filter { $0.state == .warning }.count,
            fail: moduleResults.filter { $0.state == .fail }.count,
            controllersSeen: controllersSeen,
            runtimeLines: runtimeLinesCaptured
        )

        let report = ModuleAutoTestReport(
            sessionID: sessionID,
            generatedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            iOSVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model,
            preferenceDomain: ModuleGlassStore.prefsDomain as String,
            runtimeLogPath: ModuleGlassStore.tweakLogPath,
            nextLogControlPath: Self.nextLogControlPath,
            summary: summary,
            modules: moduleResults,
            runtimeLogDelta: delta,
            deepDiagnosticText: store.diagnosticText,
            consoleEvents: Array(store.events.prefix(160))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = (try? encoder.encode(report)) ?? Data("{}".utf8)
        reportJSON = String(data: jsonData, encoding: .utf8) ?? "{}"
        reportText = makeTextReport(report)

        let logPath = "\(Self.outputDirectory)/\(sessionID)-ModuleGlass-AutoTest.log"
        let jsonPath = "\(Self.outputDirectory)/\(sessionID)-ModuleGlass-AutoTest.json"
        do {
            try Data(reportText.utf8).write(to: URL(fileURLWithPath: logPath), options: .atomic)
            try jsonData.write(to: URL(fileURLWithPath: jsonPath), options: .atomic)
            localLogPath = logPath
            localJSONPath = jsonPath
            store.record(.success, "AUTO-TEST saved local report: \(logPath)")
        } catch {
            store.record(.error, "AUTO-TEST report save failed: \(error.localizedDescription)")
        }

        restoreNextLogControl(originalData: originalNextLogData)
        postDarwin("com.nextsolution.nextlog/control.changed")

        if autoUploadWhenTokenAvailable && !store.githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            phase = "Uploading test log to NextSolution"
            progress = 0.96
            await upload(store: store, sessionID: sessionID)
        }

        progress = 1.0
        running = false
        phase = summary.fail > 0 ? "Completed with \(summary.fail) failure(s)" : "Automatic test complete"
        UINotificationFeedbackGenerator().notificationOccurred(summary.fail > 0 ? .error : .success)
        store.record(summary.fail > 0 ? .warning : .success, "AUTO-TEST \(sessionID) complete: pass=\(summary.pass) native=\(summary.native) notObserved=\(summary.notObserved) warning=\(summary.warning) fail=\(summary.fail) controllers=\(summary.controllersSeen)")
    }

    func upload(store: ModuleGlassStore, sessionID: String? = nil) async {
        guard !reportText.isEmpty, !reportJSON.isEmpty else {
            store.record(.warning, "AUTO-TEST upload requested before a report existed")
            return
        }
        let token = store.githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            phase = "Log ready locally — add GitHub token to upload"
            return
        }

        let stamp = sessionID ?? Self.sessionStamp()
        let base = "transfer/uploads/moduleglass/autotest/\(stamp)-ModuleGlass-AutoTest"
        let textPath = "\(base).log"
        let jsonPath = "\(base).json"
        let uploader = GitHubLogUploader()

        do {
            try await uploader.upload(path: textPath, data: Data(reportText.utf8), token: token, commitMessage: "Upload Module Glass auto-test log \(stamp)")
            try await uploader.upload(path: jsonPath, data: Data(reportJSON.utf8), token: token, commitMessage: "Upload Module Glass auto-test JSON \(stamp)")
            uploadedTextPath = textPath
            uploadedJSONPath = jsonPath
            store.lastUploaded = UploadedDiagnostic(textPath: textPath, jsonPath: jsonPath)
            store.record(.success, "AUTO-TEST uploaded: \(textPath) and \(jsonPath)")
        } catch {
            phase = "Auto-test finished; upload failed"
            store.record(.error, "AUTO-TEST upload failed: \(error.localizedDescription)")
        }
    }

    func clear() {
        guard !running else { return }
        progress = 0
        phase = "Ready"
        results = []
        reportText = ""
        reportJSON = ""
        localLogPath = nil
        localJSONPath = nil
        uploadedTextPath = nil
        uploadedJSONPath = nil
        controllersSeen = 0
        runtimeLinesCaptured = 0
        controlCenterNeeded = false
    }

    private func evaluate(slot: ModuleSlot, image: ModuleImageInfo, runtimeLine: String?) -> ModuleAutoTestResult {
        let observed = runtimeLine != nil
        let strategy = runtimeLine.flatMap { field("strategy", in: $0) }

        let state: ModuleAutoTestState
        let reason: String

        if image.exists && !image.decodes {
            state = .fail
            reason = "JPEG exists but UIKit cannot decode it"
        } else if !image.exists {
            state = .native
            reason = observed ? "No custom JPEG; runtime correctly uses/removes custom background" : "No custom JPEG configured for this module"
        } else if let runtimeLine {
            if runtimeLine.contains("imageLoaded=1") {
                state = .pass
                reason = "Custom JPEG decoded and runtime reported imageLoaded=1\(strategy.map { " using \($0)" } ?? "")"
            } else if runtimeLine.contains("expanded-bypass") {
                state = .warning
                reason = "Module was observed only in expanded state; compact renderer was bypassed"
            } else if runtimeLine.contains("enabled=0") {
                state = .warning
                reason = "Runtime was observed but Module Glass was disabled"
            } else if runtimeLine.contains("exists=1") && runtimeLine.contains("result=removed") {
                state = .fail
                reason = "Runtime saw the custom image file but removed the image view"
            } else {
                state = .warning
                reason = "Runtime observed the module but did not confirm imageLoaded=1"
            }
        } else {
            state = .notObserved
            reason = "Custom JPEG is valid, but this module did not appear in the captured Control Center session"
        }

        return ModuleAutoTestResult(
            moduleID: slot.id,
            title: slot.title,
            state: state,
            reason: reason,
            imageExists: image.exists,
            imageDecodes: image.decodes,
            imageBytes: image.sizeBytes,
            imageWidth: image.width,
            imageHeight: image.height,
            runtimeObserved: observed,
            runtimeStrategy: strategy,
            runtimeLine: runtimeLine
        )
    }

    private func logLevel(for state: ModuleAutoTestState) -> ConsoleEvent.Level {
        switch state {
        case .pass: return .success
        case .native: return .info
        case .notObserved, .warning: return .warning
        case .fail: return .error
        }
    }

    private func enableRuntimeDiagnostics() throws {
        var dictionary = readPlistDictionary(path: Self.nextLogControlPath)
        dictionary["enabled"] = true
        dictionary["activeTweak"] = "ModuleGlass"
        dictionary["collector"] = "ModuleGlassDeveloperConsole"
        dictionary["collectorVersion"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: Self.nextLogControlPath), options: .atomic)
    }

    private func restoreNextLogControl(originalData: Data?) {
        do {
            if let originalData {
                try originalData.write(to: URL(fileURLWithPath: Self.nextLogControlPath), options: .atomic)
            } else if FileManager.default.fileExists(atPath: Self.nextLogControlPath) {
                try FileManager.default.removeItem(atPath: Self.nextLogControlPath)
            }
        } catch {
            // The test report already contains the collector state. Restoration failure is non-fatal.
        }
    }

    private func readPlistDictionary(path: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any] else { return [:] }
        return dictionary
    }

    private func postDarwin(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: name as CFString),
            nil,
            nil,
            true
        )
    }

    private func fileSize(_ path: String) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func runtimeDelta(from offset: UInt64) -> String {
        guard let handle = FileHandle(forReadingAtPath: ModuleGlassStore.tweakLogPath) else { return "" }
        defer { try? handle.close() }
        do {
            let end = try handle.seekToEnd()
            guard end > 0 else { return "" }
            let start = min(offset, end)
            try handle.seek(toOffset: start)
            let data = try handle.readToEnd() ?? Data()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func observedModuleIDs(in text: String) -> Set<String> {
        var ids = Set<String>()
        for slot in ModuleSlot.all where text.contains("slot=\(slot.id)") {
            ids.insert(slot.id)
        }
        return ids
    }

    private func maxControllers(in text: String) -> Int {
        var maximum = 0
        for line in text.split(separator: "\n") where line.contains("refresh source=") && line.contains("controllers=") {
            guard let range = line.range(of: "controllers=") else { continue }
            let suffix = line[range.upperBound...]
            let digits = suffix.prefix { $0.isNumber }
            if let value = Int(digits) { maximum = max(maximum, value) }
        }
        return maximum
    }

    private func field(_ key: String, in line: String) -> String? {
        guard let range = line.range(of: "\(key)=") else { return nil }
        let suffix = line[range.upperBound...]
        let value = suffix.prefix { !$0.isWhitespace }
        return value.isEmpty ? nil : String(value)
    }

    private func makeTextReport(_ report: ModuleAutoTestReport) -> String {
        var out: [String] = []
        out.append("MODULE GLASS AUTOMATIC TEST REPORT")
        out.append("Session: \(report.sessionID)")
        out.append("Generated: \(report.generatedAt)")
        out.append("App: \(report.appVersion) | iOS: \(report.iOSVersion) | Device: \(report.deviceModel)")
        out.append("Runtime log: \(report.runtimeLogPath)")
        out.append("Next Log control: \(report.nextLogControlPath)")
        out.append("")
        out.append("SUMMARY")
        out.append("PASS=\(report.summary.pass) NATIVE=\(report.summary.native) NOT_OBSERVED=\(report.summary.notObserved) WARNING=\(report.summary.warning) FAIL=\(report.summary.fail)")
        out.append("controllersSeen=\(report.summary.controllersSeen) runtimeLines=\(report.summary.runtimeLines)")
        out.append("")
        out.append("MODULE RESULTS")
        for item in report.modules {
            out.append("[\(item.state.rawValue)] \(item.moduleID) / \(item.title)")
            out.append("  image exists=\(item.imageExists) decodes=\(item.imageDecodes) bytes=\(item.imageBytes) pixels=\(item.imageWidth)x\(item.imageHeight)")
            out.append("  runtime observed=\(item.runtimeObserved) strategy=\(item.runtimeStrategy ?? "<none>")")
            out.append("  \(item.reason)")
            if let line = item.runtimeLine { out.append("  runtime: \(line)") }
        }
        out.append("")
        out.append("RAW MODULE GLASS RUNTIME DELTA")
        out.append(report.runtimeLogDelta.isEmpty ? "<no new runtime log lines captured>" : report.runtimeLogDelta)
        out.append("")
        out.append("DEEP DIAGNOSTICS")
        out.append(report.deepDiagnosticText)
        out.append("")
        out.append("CONSOLE EVENTS")
        let iso = ISO8601DateFormatter()
        for event in report.consoleEvents {
            out.append("[\(iso.string(from: event.date))] [\(event.level.rawValue)] \(event.message)")
        }
        return out.joined(separator: "\n")
    }

    private static func sessionStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
