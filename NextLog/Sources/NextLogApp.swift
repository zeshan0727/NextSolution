import SwiftUI
import Foundation
import CoreFoundation

struct TweakTarget: Identifiable, Hashable {
    let slug: String
    let name: String
    let packageID: String
    let version: String
    let logFile: String
    let aliases: [String]
    var id: String { packageID.isEmpty ? slug : packageID }
}

extension TweakTarget {
    static let fallback: [TweakTarget] = [
        .init(slug: "module-glass", name: "Module Glass", packageID: "com.nextsolution.nextaura.cc-module-backgrounds", version: "", logFile: "module-glass.log", aliases: ["module glass", "cc module backgrounds", "module backgrounds", "cc backgrounds"]),
        .init(slug: "notify-island", name: "Notify Island", packageID: "com.nextsolution.nextaura.notification-island", version: "", logFile: "notify-island.log", aliases: ["notify island", "notification island", "island"]),
        .init(slug: "notify-glow", name: "Notify Glow", packageID: "com.nextsolution.nextaura.notification-glow", version: "", logFile: "notify-glow.log", aliases: ["notify glow", "notification glow"]),
        .init(slug: "notifykit", name: "NotifyKit", packageID: "com.nextsolution.nextaura.notifications", version: "", logFile: "notifykit.log", aliases: ["notifykit", "notifications"]),
        .init(slug: "pulse", name: "Pulse", packageID: "com.nextsolution.nextaura.feedback", version: "", logFile: "pulse.log", aliases: ["pulse", "haptics"]),
        .init(slug: "therma", name: "Therma", packageID: "com.nextsolution.nextaura.thermal-sweat", version: "", logFile: "therma.log", aliases: ["therma", "thermal"]),
        .init(slug: "homeflow", name: "HomeFlow", packageID: "com.nextsolution.nextaura.home-screen", version: "", logFile: "homeflow.log", aliases: ["homeflow", "home screen"]),
        .init(slug: "dockcraft", name: "DockCraft", packageID: "com.nextsolution.nextaura.dock-folders", version: "", logFile: "dockcraft.log", aliases: ["dockcraft", "dock folders"]),
        .init(slug: "lockcraft", name: "LockCraft", packageID: "com.nextsolution.nextaura.lock-screen", version: "", logFile: "lockcraft.log", aliases: ["lockcraft", "lock screen"]),
        .init(slug: "statuskit", name: "StatusKit", packageID: "com.nextsolution.nextaura.status-bar", version: "", logFile: "statuskit.log", aliases: ["statuskit", "status bar"]),
        .init(slug: "controlkit", name: "ControlKit", packageID: "com.nextsolution.nextaura.control-center", version: "", logFile: "controlkit.log", aliases: ["controlkit", "control center"]),
        .init(slug: "control-deck", name: "Control Deck", packageID: "com.nextsolution.nextaura.cc-second-page", version: "", logFile: "control-deck.log", aliases: ["control deck", "cc second page"]),
        .init(slug: "nowplay", name: "NowPlay", packageID: "com.nextsolution.nextaura.now-playing", version: "", logFile: "nowplay.log", aliases: ["nowplay", "now playing"]),
        .init(slug: "switchdeck", name: "SwitchDeck", packageID: "com.nextsolution.nextaura.app-switcher", version: "", logFile: "switchdeck.log", aliases: ["switchdeck", "app switcher"]),
        .init(slug: "hudkit", name: "HUDKit", packageID: "com.nextsolution.nextaura.system-overlays", version: "", logFile: "hudkit.log", aliases: ["hudkit", "hud", "overlays"]),
        .init(slug: "motion", name: "Motion", packageID: "com.nextsolution.nextaura.animations", version: "", logFile: "motion.log", aliases: ["motion", "animations"]),
        .init(slug: "rescue", name: "Rescue", packageID: "com.nextsolution.nextaura.safety-recovery", version: "", logFile: "rescue.log", aliases: ["rescue", "safety recovery"]),
        .init(slug: "next-quick-reminder", name: "Next Quick Reminder", packageID: "com.nextsolution.nextquickreminder", version: "", logFile: "next-quick-reminder.log", aliases: ["next quick reminder", "quick reminder"])
    ]
}

@MainActor
final class DiagnosticModel: ObservableObject {
    @Published var command = "module glass"
    @Published var targets: [TweakTarget]
    @Published var selected: TweakTarget
    @Published var isRunning = false
    @Published var status = "Ready"
    @Published var liveLog = "No diagnostic session running."
    @Published var reportURL: URL?
    @Published var lastError: String?
    @Published var manifestStatus = "Built-in profiles"

    private let sharedDirectory = "/var/mobile/Library/Logs/NextSolution"
    private let reportsDirectory = "/var/mobile/Library/Logs/NextSolution/Reports"
    private let controlPath = "/var/mobile/Library/Preferences/com.nextsolution.nextlog.plist"
    private let preferredManifestPath = "/var/mobile/Library/Preferences/com.nextsolution.nextdiagnostics.manifest.plist"
    private let controlNotification = "com.nextsolution.nextlog/control.changed"
    private var sessionID = UUID().uuidString
    private var startedAt = Date()
    private var timer: Timer?
    private var emptyPolls = 0

    init() {
        let loaded = Self.loadManifestTargets()
        let resolvedTargets = loaded.targets.isEmpty ? TweakTarget.fallback : loaded.targets
        targets = resolvedTargets
        selected = resolvedTargets.first(where: { $0.name == "Module Glass" }) ?? resolvedTargets[0]
        manifestStatus = loaded.targets.isEmpty ? "Built-in profiles · install Next Diagnostics Runtime" : "Repo manifest · \(loaded.targets.count) tweaks"
    }

    func reloadTargets() {
        let oldID = selected.id
        let loaded = Self.loadManifestTargets()
        if loaded.targets.isEmpty {
            targets = TweakTarget.fallback
            manifestStatus = "Built-in profiles · install Next Diagnostics Runtime"
        } else {
            targets = loaded.targets
            manifestStatus = "Repo manifest · \(targets.count) tweaks"
        }
        selected = targets.first(where: { $0.id == oldID }) ?? targets.first(where: { normalize($0.name) == normalize(command) }) ?? targets[0]
    }

    func resolveCommand() -> TweakTarget? {
        let normalized = normalize(command)
        guard !normalized.isEmpty else { return nil }
        return targets.first { target in
            if normalize(target.name) == normalized || normalize(target.slug) == normalized || normalize(target.packageID) == normalized { return true }
            if target.aliases.contains(where: { normalize($0) == normalized }) { return true }
            return target.aliases.contains(where: {
                let alias = normalize($0)
                return !alias.isEmpty && (normalized.contains(alias) || alias.contains(normalized))
            })
        }
    }

    func startFromCommand() {
        reloadTargets()
        guard let target = resolveCommand() else {
            lastError = "I couldn't match that tweak. Tap Choose Tweak or type its tweak name, for example ‘module glass’."
            return
        }
        selected = target
        start(target)
    }

    func start(_ target: TweakTarget) {
        stopTimer()
        reportURL = nil
        lastError = nil
        selected = target
        sessionID = UUID().uuidString
        startedAt = Date()
        emptyPolls = 0

        do {
            try FileManager.default.createDirectory(atPath: sharedDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: reportsDirectory, withIntermediateDirectories: true)
            let logPath = path(for: target)
            let previous = sharedDirectory + "/" + target.slug + ".previous.log"
            if FileManager.default.fileExists(atPath: logPath) {
                try? FileManager.default.removeItem(atPath: previous)
                try? FileManager.default.moveItem(atPath: logPath, toPath: previous)
            }
            FileManager.default.createFile(atPath: logPath, contents: nil)
            try writeControl(enabled: true, target: target)
            postControlChanged()
            isRunning = true
            status = "Capturing \(target.name)"
            liveLog = "Waiting for \(target.name) heartbeat…\n\nNext Diagnostics Runtime should report the target process and loaded tweak dylib immediately. Then reproduce the actual problem."
            refreshLog()
            timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshLog() }
            }
        } catch {
            isRunning = false
            status = "Could not start"
            lastError = "Next Log could not access the shared diagnostic folder: \(error.localizedDescription). Install this TIPA with TrollStore so its diagnostic entitlements are preserved."
        }
    }

    func stopAndBuildReport() {
        guard isRunning else { return }
        do {
            try writeControl(enabled: false, target: selected)
            postControlChanged()
        } catch {
            lastError = "Capture stopped, but the control file could not be updated: \(error.localizedDescription)"
        }
        isRunning = false
        stopTimer()
        refreshLog()
        buildReport()
        status = "Report ready"
    }

    func clearCurrentLog() {
        let logPath = path(for: selected)
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
        emptyPolls = 0
        refreshLog()
    }

    private func writeControl(enabled: Bool, target: TweakTarget) throws {
        let values: NSDictionary = [
            "enabled": enabled,
            "activeTweak": target.slug,
            "displayName": target.name,
            "packageID": target.packageID,
            "version": target.version,
            "logFile": target.logFile,
            "sessionID": sessionID,
            "startedAt": ISO8601DateFormatter().string(from: startedAt)
        ]
        let directory = (controlPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        guard values.write(toFile: controlPath, atomically: true) else {
            throw NSError(domain: "NextLog", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to write diagnostic control file"])
        }
    }

    private func postControlChanged() {
        let name = CFNotificationName(rawValue: controlNotification as CFString)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, nil, nil, true)
    }

    private func path(for target: TweakTarget) -> String {
        sharedDirectory + "/" + target.logFile
    }

    private func refreshLog() {
        let logPath = path(for: selected)
        guard let data = FileManager.default.contents(atPath: logPath), !data.isEmpty else {
            if isRunning {
                emptyPolls += 1
                if emptyPolls >= 4 {
                    liveLog = "No diagnostic heartbeat has arrived yet.\n\n1. Make sure Next Diagnostics Runtime is installed from nextsolution.cc.\n2. Respring after installing/updating it.\n3. If this tweak runs inside an app, open that app while capture is active.\n\nIf it still stays empty, the report itself proves the diagnostics runtime did not inject into the target process."
                } else {
                    liveLog = "Capture is active. Waiting for the diagnostic runtime…"
                }
            }
            return
        }
        emptyPolls = 0
        let text = String(decoding: data, as: UTF8.self)
        liveLog = String(text.suffix(28_000))
    }

    private func buildReport() {
        let ended = Date()
        let logPath = path(for: selected)
        let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "<no log output>"
        let device = UIDevice.current
        let report = """
        NEXT LOG DIAGNOSTIC REPORT
        ==========================
        Tweak: \(selected.name)
        Package: \(selected.packageID.isEmpty ? "<unknown>" : selected.packageID)
        Package Version: \(selected.version.isEmpty ? "<unknown>" : selected.version)
        Tweak ID: \(selected.slug)
        Session: \(sessionID)
        Started: \(ISO8601DateFormatter().string(from: startedAt))
        Ended: \(ISO8601DateFormatter().string(from: ended))
        Device: \(device.model)
        System: \(device.systemName) \(device.systemVersion)
        App: Next Log 1.1.0
        Profile Source: \(manifestStatus)
        Source log: \(logPath)

        LOG OUTPUT
        ----------
        \(log)
        """
        let stamp = ISO8601DateFormatter().string(from: ended).replacingOccurrences(of: ":", with: "-")
        let filename = "NextLog-\(selected.slug)-\(stamp).txt"
        let url = URL(fileURLWithPath: reportsDirectory).appendingPathComponent(filename)
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            reportURL = url
        } catch {
            lastError = "The log was captured, but the report file could not be created: \(error.localizedDescription)"
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func loadManifestTargets() -> (targets: [TweakTarget], path: String?) {
        let fm = FileManager.default
        var candidates = [
            "/var/mobile/Library/Preferences/com.nextsolution.nextdiagnostics.manifest.plist",
            "/var/jb/Library/Application Support/NextDiagnostics/manifest.plist",
            "/Library/Application Support/NextDiagnostics/manifest.plist"
        ]

        let rootHide = "/var/containers/Bundle/tweaksupport"
        if let roots = try? fm.contentsOfDirectory(atPath: rootHide) {
            for item in roots {
                candidates.append(rootHide + "/" + item + "/Library/Application Support/NextDiagnostics/manifest.plist")
            }
        }

        for path in candidates where fm.fileExists(atPath: path) {
            guard let manifest = NSDictionary(contentsOfFile: path) as? [String: Any],
                  let rows = manifest["tweaks"] as? [[String: Any]] else { continue }
            let values: [TweakTarget] = rows.compactMap { row in
                guard let slug = row["slug"] as? String,
                      let name = row["name"] as? String,
                      let logFile = row["logFile"] as? String else { return nil }
                return TweakTarget(
                    slug: slug,
                    name: name,
                    packageID: row["packageID"] as? String ?? "",
                    version: row["version"] as? String ?? "",
                    logFile: logFile,
                    aliases: row["aliases"] as? [String] ?? []
                )
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !values.isEmpty { return (values, path) }
        }
        return ([], nil)
    }
}

@main
struct NextLogApp: App {
    @StateObject private var model = DiagnosticModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: DiagnosticModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    commandCard
                    sessionCard
                    logCard
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Next Log")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Next Log", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
                Button("OK", role: .cancel) { model.lastError = nil }
            } message: {
                Text(model.lastError ?? "")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 52, height: 52)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Tweak Diagnostics")
                    .font(.headline)
                Text("\(model.manifestStatus). Start one focused capture, reproduce the problem, then share the report.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var commandCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostic Command")
                .font(.headline)
            TextField("Example: module glass", text: $model.command)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                model.startFromCommand()
            } label: {
                Label(model.isRunning ? "Restart Diagnostic" : "Run Diagnostic", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)

            Menu {
                ForEach(model.targets) { target in
                    Button(target.version.isEmpty ? target.name : "\(target.name)  \(target.version)") {
                        model.command = target.name
                        model.selected = target
                    }
                }
            } label: {
                Label("Choose Tweak", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                model.reloadTargets()
            } label: {
                Label("Reload Repo Tweak List", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selected.name)
                        .font(.headline)
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(model.isRunning ? Color.green : Color.secondary)
                    if !model.selected.packageID.isEmpty {
                        Text(model.selected.packageID + (model.selected.version.isEmpty ? "" : " · " + model.selected.version))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Circle()
                    .fill(model.isRunning ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 10, height: 10)
            }

            if model.isRunning {
                Text("Keep capture running, reproduce the issue once, then stop. The shared runtime provides injection/dylib status; instrumented tweaks can add deeper event lines to the same report.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    model.stopAndBuildReport()
                } label: {
                    Label("Stop & Prepare Report", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else if let url = model.reportURL {
                ShareLink(item: url) {
                    Label("Share Diagnostic Report", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Log")
                    .font(.headline)
                Spacer()
                Button("Clear") { model.clearCurrentLog() }
                    .font(.caption)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text(model.liveLog)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 180, maxHeight: 340)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
