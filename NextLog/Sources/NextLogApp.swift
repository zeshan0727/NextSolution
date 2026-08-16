import SwiftUI
import Foundation
import CoreFoundation

struct TweakTarget: Identifiable, Hashable {
    let slug: String
    let name: String
    let logFile: String
    let aliases: [String]
    var id: String { slug }
}

extension TweakTarget {
    static let known: [TweakTarget] = [
        .init(slug: "module-glass", name: "Module Glass", logFile: "module-glass.log", aliases: ["module glass", "cc module backgrounds", "module backgrounds", "cc backgrounds"]),
        .init(slug: "notify-island", name: "Notify Island", logFile: "notify-island.log", aliases: ["notify island", "notification island", "island"]),
        .init(slug: "notify-glow", name: "Notify Glow", logFile: "notify-glow.log", aliases: ["notify glow", "notification glow"]),
        .init(slug: "notifykit", name: "NotifyKit", logFile: "notifykit.log", aliases: ["notifykit", "notifications"]),
        .init(slug: "pulse", name: "Pulse", logFile: "pulse.log", aliases: ["pulse", "haptics"]),
        .init(slug: "therma", name: "Therma", logFile: "therma.log", aliases: ["therma", "thermal"]),
        .init(slug: "homeflow", name: "HomeFlow", logFile: "homeflow.log", aliases: ["homeflow", "home screen"]),
        .init(slug: "dockcraft", name: "DockCraft", logFile: "dockcraft.log", aliases: ["dockcraft", "dock folders"]),
        .init(slug: "lockcraft", name: "LockCraft", logFile: "lockcraft.log", aliases: ["lockcraft", "lock screen"]),
        .init(slug: "statuskit", name: "StatusKit", logFile: "statuskit.log", aliases: ["statuskit", "status bar"]),
        .init(slug: "controlkit", name: "ControlKit", logFile: "controlkit.log", aliases: ["controlkit", "control center"]),
        .init(slug: "control-deck", name: "Control Deck", logFile: "control-deck.log", aliases: ["control deck", "cc second page"]),
        .init(slug: "nowplay", name: "NowPlay", logFile: "nowplay.log", aliases: ["nowplay", "now playing"]),
        .init(slug: "switchdeck", name: "SwitchDeck", logFile: "switchdeck.log", aliases: ["switchdeck", "app switcher"]),
        .init(slug: "hudkit", name: "HUDKit", logFile: "hudkit.log", aliases: ["hudkit", "hud", "overlays"]),
        .init(slug: "motion", name: "Motion", logFile: "motion.log", aliases: ["motion", "animations"]),
        .init(slug: "rescue", name: "Rescue", logFile: "rescue.log", aliases: ["rescue", "safety recovery"]),
        .init(slug: "next-quick-reminder", name: "Next Quick Reminder", logFile: "next-quick-reminder.log", aliases: ["next quick reminder", "quick reminder"])
    ]
}

@MainActor
final class DiagnosticModel: ObservableObject {
    @Published var command = "module glass"
    @Published var selected: TweakTarget = .known[0]
    @Published var isRunning = false
    @Published var status = "Ready"
    @Published var liveLog = "No diagnostic session running."
    @Published var reportURL: URL?
    @Published var lastError: String?

    private let sharedDirectory = "/var/mobile/Library/Logs/NextSolution"
    private let reportsDirectory = "/var/mobile/Library/Logs/NextSolution/Reports"
    private let controlPath = "/var/mobile/Library/Preferences/com.nextsolution.nextlog.plist"
    private let controlNotification = "com.nextsolution.nextlog/control.changed"
    private var sessionID = UUID().uuidString
    private var startedAt = Date()
    private var timer: Timer?

    func resolveCommand() -> TweakTarget? {
        let normalized = normalize(command)
        guard !normalized.isEmpty else { return nil }
        return TweakTarget.known.first { target in
            if normalize(target.name) == normalized || normalize(target.slug) == normalized { return true }
            if target.aliases.contains(where: { normalize($0) == normalized }) { return true }
            return target.aliases.contains(where: { normalized.contains(normalize($0)) })
        }
    }

    func startFromCommand() {
        guard let target = resolveCommand() else {
            lastError = "I couldn't match that tweak. Choose a tweak below or type its name, for example ‘module glass’."
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
            liveLog = "Waiting for \(target.name) events…\n\nReproduce the problem now."
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
        refreshLog()
    }

    private func writeControl(enabled: Bool, target: TweakTarget) throws {
        let values: NSDictionary = [
            "enabled": enabled,
            "activeTweak": target.slug,
            "displayName": target.name,
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
                liveLog = "Capture is active, but no log lines have arrived yet.\n\nOpen or use the feature that is failing, then return here."
            }
            return
        }
        let text = String(decoding: data, as: UTF8.self)
        liveLog = String(text.suffix(24_000))
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
        Tweak ID: \(selected.slug)
        Session: \(sessionID)
        Started: \(ISO8601DateFormatter().string(from: startedAt))
        Ended: \(ISO8601DateFormatter().string(from: ended))
        Device: \(device.model)
        System: \(device.systemName) \(device.systemVersion)
        App: Next Log 1.0.0
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
                Text("Start one focused capture, reproduce the problem, then share the report.")
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
                ForEach(TweakTarget.known) { target in
                    Button(target.name) {
                        model.command = target.name
                        model.selected = target
                    }
                }
            } label: {
                Label("Choose Tweak", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
                }
                Spacer()
                Circle()
                    .fill(model.isRunning ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 10, height: 10)
            }

            if model.isRunning {
                Text("Keep capture running, reproduce the issue once, then stop. Only the selected tweak should write detailed diagnostic lines.")
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
