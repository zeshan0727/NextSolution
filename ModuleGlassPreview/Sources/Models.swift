import Foundation
import SwiftUI

struct ModuleSlot: Identifiable, Hashable, Codable {
    enum Shape: String, Codable, CaseIterable {
        case wide
        case pill
        case small

        var aspectRatio: CGFloat {
            switch self {
            case .wide: return 2.0
            case .pill: return 0.50
            case .small: return 1.0
            }
        }

        var exportSize: CGSize {
            switch self {
            case .wide: return CGSize(width: 1200, height: 600)
            case .pill: return CGSize(width: 600, height: 1200)
            case .small: return CGSize(width: 800, height: 800)
            }
        }
    }

    let id: String
    let title: String
    let symbol: String
    let shape: Shape
    let subtitle: String

    static let all: [ModuleSlot] = [
        .init(id: "connectivity", title: "Connectivity", symbol: "antenna.radiowaves.left.and.right", shape: .wide, subtitle: "Wi-Fi, Bluetooth and network controls"),
        .init(id: "media", title: "Now Playing", symbol: "play.fill", shape: .wide, subtitle: "Media controls and artwork surface"),
        .init(id: "brightness", title: "Brightness", symbol: "sun.max.fill", shape: .pill, subtitle: "Vertical display brightness control"),
        .init(id: "volume", title: "Volume", symbol: "speaker.wave.2.fill", shape: .pill, subtitle: "Vertical system volume control"),
        .init(id: "screenrecording", title: "Screen Recording", symbol: "record.circle", shape: .small, subtitle: "Screen recorder toggle"),
        .init(id: "screenmirroring", title: "Screen Mirroring", symbol: "rectangle.on.rectangle", shape: .small, subtitle: "AirPlay screen mirroring"),
        .init(id: "orientation", title: "Orientation Lock", symbol: "lock.rotation", shape: .small, subtitle: "Portrait orientation lock"),
        .init(id: "lowpower", title: "Low Power", symbol: "battery.25", shape: .small, subtitle: "Low Power Mode toggle"),
        .init(id: "focus", title: "Focus", symbol: "moon.fill", shape: .small, subtitle: "Focus / Do Not Disturb"),
        .init(id: "flashlight", title: "Flashlight", symbol: "flashlight.on.fill", shape: .small, subtitle: "Flashlight control"),
        .init(id: "timer", title: "Timer", symbol: "timer", shape: .small, subtitle: "Timer shortcut"),
        .init(id: "calculator", title: "Calculator", symbol: "plus.forwardslash.minus", shape: .small, subtitle: "Calculator shortcut"),
        .init(id: "camera", title: "Camera", symbol: "camera.fill", shape: .small, subtitle: "Camera shortcut"),
        .init(id: "hearing", title: "Hearing", symbol: "ear", shape: .small, subtitle: "Hearing controls"),
        .init(id: "notes", title: "Quick Note", symbol: "note.text", shape: .small, subtitle: "Quick Note control"),
        .init(id: "home", title: "Home", symbol: "house.fill", shape: .small, subtitle: "Home controls")
    ]

    static func slot(_ id: String) -> ModuleSlot {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

struct ConsoleEvent: Identifiable, Codable, Hashable {
    enum Level: String, Codable {
        case info = "INFO"
        case success = "OK"
        case warning = "WARN"
        case error = "ERROR"
    }

    let id: UUID
    let date: Date
    let level: Level
    let message: String

    init(level: Level, message: String) {
        self.id = UUID()
        self.date = Date()
        self.level = level
        self.message = message
    }
}

struct ModuleImageInfo: Codable, Hashable, Identifiable {
    var id: String { moduleID }
    let moduleID: String
    let title: String
    let path: String
    let exists: Bool
    let sizeBytes: Int64
    let width: Int
    let height: Int
    let modifiedAt: Date?
    let decodes: Bool
}

struct PackageEvidence: Codable, Hashable {
    let statusPath: String
    let package: String
    let version: String?
    let installed: Bool
}

struct DiagnosticReport: Codable {
    struct Device: Codable {
        let model: String
        let systemName: String
        let systemVersion: String
        let appVersion: String
        let appBuild: String
        let bundleID: String
    }

    struct Preferences: Codable {
        let domain: String
        let enabled: Bool
        let opacity: Double
        let removeBlur: Bool
        let volumeIconColorEnabled: Bool
        let volumeIconColor: String
    }

    struct Paths: Codable {
        let imageDirectory: String
        let tweakLog: String
        let consoleLog: String
        let imageDirectoryWritable: Bool
    }

    let generatedAt: Date
    let device: Device
    let preferences: Preferences
    let paths: Paths
    let images: [ModuleImageInfo]
    let packages: [PackageEvidence]
    let notifications: [String]
    let events: [ConsoleEvent]
    let tweakLogTail: String
    let consoleLogTail: String
}

struct UploadedDiagnostic: Hashable {
    let textPath: String
    let jsonPath: String
}
