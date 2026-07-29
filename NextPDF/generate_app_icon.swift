import AppKit
import Foundation

let fileManager = FileManager.default
let nextPDFRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let repositoryRoot = nextPDFRoot.deletingLastPathComponent()
let sourcePartsDirectory = repositoryRoot.appendingPathComponent("AcademySMSLab", isDirectory: true)
let buildRoot = nextPDFRoot.appendingPathComponent("AcademyBuild", isDirectory: true)
let archiveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AcademySMSLab-source.tgz")

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "AcademySMSLabBuild",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "Command failed: \(executable) \(arguments.joined(separator: " "))"]
        )
    }
}

let sourceParts = try fileManager.contentsOfDirectory(
    at: sourcePartsDirectory,
    includingPropertiesForKeys: nil
)
.filter { $0.lastPathComponent.hasPrefix("source.tgz.b64.part-") }
.sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !sourceParts.isEmpty else {
    fatalError("Academy SMS Lab source bundle parts were not found")
}

var encodedArchive = Data()
for part in sourceParts {
    encodedArchive.append(try Data(contentsOf: part))
}

guard let archiveData = Data(base64Encoded: encodedArchive, options: .ignoreUnknownCharacters) else {
    fatalError("Unable to decode Academy SMS Lab source archive")
}

try archiveData.write(to: archiveURL, options: .atomic)
try? fileManager.removeItem(at: buildRoot)
try fileManager.createDirectory(at: buildRoot, withIntermediateDirectories: true)
try run("/usr/bin/tar", [
    "-xzf", archiveURL.path,
    "-C", buildRoot.path,
    "--strip-components=1"
])

let iconURL = buildRoot
    .appendingPathComponent("iOS/AcademySMSLab/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
    .appendingPathComponent("AppIcon.png")

let canvasSize = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvasSize)
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create graphics context")
}

let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.025, green: 0.055, blue: 0.15, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.08, green: 0.36, blue: 0.84, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.08, green: 0.72, blue: 0.86, alpha: 1).cgColor
    ] as CFArray,
    locations: [0, 0.58, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 90, y: 980),
    end: CGPoint(x: 940, y: 40),
    options: []
)

let cardRect = NSRect(x: 92, y: 92, width: 840, height: 840)
let card = NSBezierPath(roundedRect: cardRect, xRadius: 210, yRadius: 210)
context.saveGState()
context.setShadow(offset: .zero, blur: 44, color: NSColor.black.withAlphaComponent(0.38).cgColor)
NSColor(calibratedWhite: 0.04, alpha: 0.9).setFill()
card.fill()
context.restoreGState()

let bubbleRect = NSRect(x: 216, y: 330, width: 592, height: 400)
let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 115, yRadius: 115)
NSColor.white.setFill()
bubble.fill()

let tail = NSBezierPath()
tail.move(to: NSPoint(x: 350, y: 350))
tail.line(to: NSPoint(x: 290, y: 220))
tail.line(to: NSPoint(x: 470, y: 340))
tail.close()
NSColor.white.setFill()
tail.fill()

for x in [360.0, 512.0, 664.0] {
    let dot = NSBezierPath(ovalIn: NSRect(x: x - 38, y: 492, width: 76, height: 76))
    NSColor(calibratedRed: 0.08, green: 0.38, blue: 0.82, alpha: 1).setFill()
    dot.fill()
}

let badge = NSBezierPath(ovalIn: NSRect(x: 652, y: 650, width: 190, height: 190))
NSColor(calibratedRed: 0.12, green: 0.78, blue: 0.48, alpha: 1).setFill()
badge.fill()

let check = NSBezierPath()
check.move(to: NSPoint(x: 704, y: 742))
check.line(to: NSPoint(x: 744, y: 700))
check.line(to: NSPoint(x: 800, y: 776))
check.lineWidth = 24
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor.white.setStroke()
check.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode app icon")
}

try fileManager.createDirectory(at: iconURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: iconURL, options: .atomic)

if let requestedPath = CommandLine.arguments.dropFirst().first {
    let requestedURL = URL(fileURLWithPath: requestedPath)
    try fileManager.createDirectory(at: requestedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: requestedURL, options: .atomic)
}

print("Reconstructed Academy SMS Lab source at \(buildRoot.path)")
print("Generated Academy SMS Lab icon at \(iconURL.path)")
