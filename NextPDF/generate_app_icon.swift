import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "NextPDF/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let canvasSize = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvasSize)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create graphics context")
}

let fullRect = CGRect(origin: .zero, size: canvasSize)
let backgroundColors = [
    NSColor(calibratedRed: 0.005, green: 0.012, blue: 0.035, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.02, green: 0.055, blue: 0.13, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.005, green: 0.015, blue: 0.05, alpha: 1).cgColor
] as CFArray
let backgroundGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: backgroundColors, locations: [0, 0.5, 1])!
context.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: 80, y: 980),
    end: CGPoint(x: 940, y: 40),
    options: []
)

let cardRect = NSRect(x: 54, y: 54, width: 916, height: 916)
let card = NSBezierPath(roundedRect: cardRect, xRadius: 210, yRadius: 210)
context.saveGState()
context.setShadow(offset: .zero, blur: 46, color: NSColor(calibratedRed: 0.0, green: 0.45, blue: 1.0, alpha: 0.95).cgColor)
NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.08, alpha: 1).setFill()
card.fill()
context.restoreGState()

let border = NSBezierPath(roundedRect: NSInsetRect(cardRect, 10, 10), xRadius: 196, yRadius: 196)
border.lineWidth = 11
NSColor(calibratedRed: 0.02, green: 0.48, blue: 1.0, alpha: 0.9).setStroke()
border.stroke()

let page = NSBezierPath()
page.move(to: NSPoint(x: 282, y: 758))
page.line(to: NSPoint(x: 626, y: 758))
page.line(to: NSPoint(x: 742, y: 644))
page.line(to: NSPoint(x: 742, y: 272))
page.curve(to: NSPoint(x: 678, y: 208), controlPoint1: NSPoint(x: 742, y: 236), controlPoint2: NSPoint(x: 714, y: 208))
page.line(to: NSPoint(x: 282, y: 208))
page.curve(to: NSPoint(x: 218, y: 272), controlPoint1: NSPoint(x: 246, y: 208), controlPoint2: NSPoint(x: 218, y: 236))
page.line(to: NSPoint(x: 218, y: 694))
page.curve(to: NSPoint(x: 282, y: 758), controlPoint1: NSPoint(x: 218, y: 730), controlPoint2: NSPoint(x: 246, y: 758))
page.lineWidth = 44
page.lineJoinStyle = .round
page.lineCapStyle = .round
context.saveGState()
context.setShadow(offset: .zero, blur: 24, color: NSColor(calibratedRed: 0.0, green: 0.45, blue: 1.0, alpha: 0.75).cgColor)
NSColor.white.setStroke()
page.stroke()
context.restoreGState()

let lowerAccent = NSBezierPath()
lowerAccent.move(to: NSPoint(x: 430, y: 208))
lowerAccent.line(to: NSPoint(x: 678, y: 208))
lowerAccent.curve(to: NSPoint(x: 742, y: 272), controlPoint1: NSPoint(x: 714, y: 208), controlPoint2: NSPoint(x: 742, y: 236))
lowerAccent.lineWidth = 44
lowerAccent.lineJoinStyle = .round
lowerAccent.lineCapStyle = .round
NSColor(calibratedRed: 0.02, green: 0.48, blue: 1.0, alpha: 1).setStroke()
lowerAccent.stroke()

let fold = NSBezierPath()
fold.move(to: NSPoint(x: 626, y: 758))
fold.line(to: NSPoint(x: 626, y: 670))
fold.curve(to: NSPoint(x: 676, y: 620), controlPoint1: NSPoint(x: 626, y: 642), controlPoint2: NSPoint(x: 648, y: 620))
fold.line(to: NSPoint(x: 742, y: 620))
fold.close()
let foldColors = [
    NSColor(calibratedRed: 0.18, green: 0.72, blue: 1.0, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.0, green: 0.35, blue: 1.0, alpha: 1).cgColor
] as CFArray
let foldGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: foldColors, locations: [0, 1])!
context.saveGState()
fold.addClip()
context.drawLinearGradient(foldGradient, start: CGPoint(x: 620, y: 760), end: CGPoint(x: 740, y: 610), options: [])
context.restoreGState()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let font = NSFont.systemFont(ofSize: 240, weight: .heavy)
let whiteAttributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
    .kern: -12
]
let blueAttributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(calibratedRed: 0.02, green: 0.48, blue: 1.0, alpha: 1),
    .paragraphStyle: paragraph,
    .kern: -12
]

let baselineY: CGFloat = 338
("PD" as NSString).draw(in: NSRect(x: 255, y: baselineY, width: 330, height: 260), withAttributes: whiteAttributes)
("F" as NSString).draw(in: NSRect(x: 560, y: baselineY, width: 205, height: 260), withAttributes: blueAttributes)

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
