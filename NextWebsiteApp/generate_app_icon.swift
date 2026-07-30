import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "NextSolution/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let canvasSize = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvasSize)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create graphics context")
}

let backgroundColors = [
    NSColor(calibratedRed: 0.42, green: 0.07, blue: 0.80, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.13, green: 0.46, blue: 0.98, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.00, green: 0.82, blue: 1.00, alpha: 1).cgColor
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: backgroundColors, locations: [0, 0.58, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 80, y: 950), end: CGPoint(x: 940, y: 80), options: [])

let cardRect = NSRect(x: 72, y: 72, width: 880, height: 880)
let card = NSBezierPath(roundedRect: cardRect, xRadius: 220, yRadius: 220)
context.saveGState()
context.setShadow(offset: .zero, blur: 48, color: NSColor.black.withAlphaComponent(0.30).cgColor)
NSColor.white.withAlphaComponent(0.12).setFill()
card.fill()
context.restoreGState()

let border = NSBezierPath(roundedRect: NSInsetRect(cardRect, 9, 9), xRadius: 208, yRadius: 208)
border.lineWidth = 10
NSColor.white.withAlphaComponent(0.44).setStroke()
border.stroke()

let globeRect = NSRect(x: 236, y: 246, width: 552, height: 552)
let globe = NSBezierPath(ovalIn: globeRect)
globe.lineWidth = 30
NSColor.white.withAlphaComponent(0.92).setStroke()
globe.stroke()

for offset in [-150.0, 0.0, 150.0] {
    let latitude = NSBezierPath()
    latitude.move(to: NSPoint(x: 265, y: 522 + offset))
    latitude.curve(
        to: NSPoint(x: 759, y: 522 + offset),
        controlPoint1: NSPoint(x: 382, y: 470 + offset),
        controlPoint2: NSPoint(x: 642, y: 470 + offset)
    )
    latitude.lineWidth = 18
    latitude.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.62).setStroke()
    latitude.stroke()
}

for horizontalScale in [0.42, 0.72] {
    let meridianRect = NSRect(
        x: 512 - (552 * horizontalScale / 2),
        y: 246,
        width: 552 * horizontalScale,
        height: 552
    )
    let meridian = NSBezierPath(ovalIn: meridianRect)
    meridian.lineWidth = 18
    NSColor.white.withAlphaComponent(0.62).setStroke()
    meridian.stroke()
}

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 195, weight: .black),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
    .kern: -10
]
("NS" as NSString).draw(in: NSRect(x: 260, y: 395, width: 504, height: 230), withAttributes: attributes)

let spark = NSBezierPath()
spark.move(to: NSPoint(x: 786, y: 760))
spark.line(to: NSPoint(x: 808, y: 818))
spark.line(to: NSPoint(x: 866, y: 840))
spark.line(to: NSPoint(x: 808, y: 862))
spark.line(to: NSPoint(x: 786, y: 920))
spark.line(to: NSPoint(x: 764, y: 862))
spark.line(to: NSPoint(x: 706, y: 840))
spark.line(to: NSPoint(x: 764, y: 818))
spark.close()
NSColor.white.setFill()
spark.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode app icon")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: outputURL, options: .atomic)
print("Generated app icon at \(outputURL.path)")
