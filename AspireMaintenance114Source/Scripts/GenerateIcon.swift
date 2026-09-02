import AppKit

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "AppIcon-1024.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

let green = NSColor(calibratedRed: 0.08, green: 0.46, blue: 0.28, alpha: 1)
let darkGreen = NSColor(calibratedRed: 0.035, green: 0.26, blue: 0.16, alpha: 1)
let gold = NSColor(calibratedRed: 0.94, green: 0.65, blue: 0.12, alpha: 1)

image.lockFocus()
let canvas = NSRect(origin: .zero, size: size)
NSGradient(colors: [darkGreen, green])!.draw(in: canvas, angle: -45)

// Soft depth rings.
NSColor.white.withAlphaComponent(0.07).setFill()
NSBezierPath(ovalIn: NSRect(x: -90, y: 140, width: 920, height: 920)).fill()
NSColor.white.withAlphaComponent(0.05).setFill()
NSBezierPath(ovalIn: NSRect(x: 260, y: -120, width: 900, height: 900)).fill()

// Main white badge.
let badge = NSBezierPath(roundedRect: NSRect(x: 142, y: 142, width: 740, height: 740), xRadius: 190, yRadius: 190)
NSColor.white.setFill()
badge.fill()

// Aspire "a" ring.
let ringRect = NSRect(x: 245, y: 252, width: 430, height: 430)
let ring = NSBezierPath(ovalIn: ringRect)
ring.lineWidth = 66
green.setStroke()
ring.stroke()

// Open the lower-right section to echo the company mark.
NSColor.white.setFill()
NSBezierPath(rect: NSRect(x: 520, y: 205, width: 260, height: 245)).fill()

// Lower gold sweep.
let sweep = NSBezierPath()
sweep.move(to: NSPoint(x: 248, y: 340))
sweep.curve(to: NSPoint(x: 665, y: 276), controlPoint1: NSPoint(x: 344, y: 220), controlPoint2: NSPoint(x: 558, y: 208))
sweep.lineWidth = 64
sweep.lineCapStyle = .round
gold.setStroke()
sweep.stroke()

// Stem and leaves.
let stem = NSBezierPath()
stem.move(to: NSPoint(x: 457, y: 415))
stem.curve(to: NSPoint(x: 515, y: 675), controlPoint1: NSPoint(x: 472, y: 520), controlPoint2: NSPoint(x: 500, y: 604))
stem.lineWidth = 25
stem.lineCapStyle = .round
green.setStroke()
stem.stroke()

func drawLeaf(_ points: [NSPoint]) {
    guard points.count == 4 else { return }
    let leaf = NSBezierPath()
    leaf.move(to: points[0])
    leaf.curve(to: points[3], controlPoint1: points[1], controlPoint2: points[2])
    leaf.curve(to: points[0], controlPoint1: NSPoint(x: points[2].x - 30, y: points[2].y - 5), controlPoint2: NSPoint(x: points[1].x - 25, y: points[1].y + 5))
    green.setFill()
    leaf.fill()
}

drawLeaf([
    NSPoint(x: 500, y: 585),
    NSPoint(x: 565, y: 610),
    NSPoint(x: 610, y: 684),
    NSPoint(x: 505, y: 641)
])
drawLeaf([
    NSPoint(x: 479, y: 525),
    NSPoint(x: 405, y: 544),
    NSPoint(x: 375, y: 622),
    NSPoint(x: 485, y: 580)
])
drawLeaf([
    NSPoint(x: 507, y: 650),
    NSPoint(x: 548, y: 704),
    NSPoint(x: 535, y: 761),
    NSPoint(x: 491, y: 685)
])

// Small wordmark.
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 74, weight: .bold),
    .foregroundColor: darkGreen,
    .paragraphStyle: paragraph,
    .kern: 4
]
"ASPIRE".draw(in: NSRect(x: 190, y: 720, width: 644, height: 90), withAttributes: attributes)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to generate Aspire app icon\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
