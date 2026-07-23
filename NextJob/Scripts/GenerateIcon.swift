import AppKit

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "AppIcon-1024.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
let canvas = NSRect(origin: .zero, size: size)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.05, green: 0.25, blue: 0.75, alpha: 1),
    NSColor(calibratedRed: 0.25, green: 0.18, blue: 0.65, alpha: 1)
])!
gradient.draw(in: canvas, angle: -45)

NSColor(calibratedWhite: 1, alpha: 0.13).setFill()
NSBezierPath(ovalIn: NSRect(x: 70, y: 120, width: 860, height: 860)).fill()

let body = NSBezierPath(roundedRect: NSRect(x: 190, y: 230, width: 644, height: 430), xRadius: 92, yRadius: 92)
NSColor.white.setFill()
body.fill()

let handle = NSBezierPath(roundedRect: NSRect(x: 350, y: 610, width: 324, height: 185), xRadius: 58, yRadius: 58)
handle.lineWidth = 52
NSColor.white.setStroke()
handle.stroke()

let band = NSBezierPath(roundedRect: NSRect(x: 190, y: 445, width: 644, height: 105), xRadius: 34, yRadius: 34)
NSColor(calibratedRed: 0.08, green: 0.42, blue: 0.95, alpha: 1).setFill()
band.fill()

let badgeRect = NSRect(x: 600, y: 155, width: 270, height: 270)
NSColor(calibratedRed: 0.12, green: 0.78, blue: 0.34, alpha: 1).setFill()
NSBezierPath(ovalIn: badgeRect).fill()
NSColor.white.setStroke()
let badgeOutline = NSBezierPath(ovalIn: badgeRect.insetBy(dx: 12, dy: 12))
badgeOutline.lineWidth = 24
badgeOutline.stroke()

let check = NSBezierPath()
check.move(to: NSPoint(x: 665, y: 286))
check.line(to: NSPoint(x: 725, y: 225))
check.line(to: NSPoint(x: 815, y: 340))
check.lineWidth = 35
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor.white.setStroke()
check.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to generate icon\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
