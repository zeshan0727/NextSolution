#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$ROOT/Resources/Assets.xcassets"
ICONSET="$ASSETS/AppIcon.appiconset"
mkdir -p "$ASSETS/AccentColor.colorset" "$ASSETS/LaunchBackground.colorset" "$ICONSET"
cat > "$ASSETS/Contents.json" <<'JSON'
{"info":{"author":"xcode","version":1}}
JSON
cat > "$ASSETS/AccentColor.colorset/Contents.json" <<'JSON'
{"colors":[{"color":{"color-space":"srgb","components":{"alpha":"1.000","blue":"0.620","green":"0.431","red":"0.047"}},"idiom":"universal"}],"info":{"author":"xcode","version":1}}
JSON
cat > "$ASSETS/LaunchBackground.colorset/Contents.json" <<'JSON'
{"colors":[{"color":{"color-space":"srgb","components":{"alpha":"1.000","blue":"0.176","green":"0.106","red":"0.035"}},"idiom":"universal"},{"appearances":[{"appearance":"luminosity","value":"dark"}],"color":{"color-space":"srgb","components":{"alpha":"1.000","blue":"0.090","green":"0.055","red":"0.020"}},"idiom":"universal"}],"info":{"author":"xcode","version":1}}
JSON
cat > "$ICONSET/Contents.json" <<'JSON'
{"images":[{"filename":"AppIcon-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
JSON
cat > "$RUNNER_TEMP/generate_kba_icon.swift" <<'SWIFT'
import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.035, green: 0.106, blue: 0.176, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let colors = [
    NSColor(calibratedRed: 0.047, green: 0.431, blue: 0.620, alpha: 1),
    NSColor(calibratedRed: 0.075, green: 0.639, blue: 0.631, alpha: 1),
    NSColor(calibratedRed: 0.847, green: 0.659, blue: 0.243, alpha: 1)
]
for (index, color) in colors.enumerated() {
    let inset = CGFloat(80 + index * 75)
    color.setStroke()
    let path = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2), xRadius: CGFloat(180 - index * 25), yRadius: CGFloat(180 - index * 25))
    path.lineWidth = 30
    path.stroke()
}
let text = "KBA" as NSString
let font = NSFont.systemFont(ofSize: 220, weight: .heavy)
let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
let measured = text.size(withAttributes: attributes)
text.draw(at: NSPoint(x: (1024 - measured.width) / 2, y: (1024 - measured.height) / 2), withAttributes: attributes)
image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not generate app icon")
}
try png.write(to: output)
SWIFT
swift "$RUNNER_TEMP/generate_kba_icon.swift" "$ICONSET/AppIcon-1024.png"
echo "Prepared KBA asset catalog"
