// Renders Resources/AppIcon.icns (a vinyl record on a dark squircle).
// Usage: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Disque-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    let scale = s / 1024

    // macOS icon grid: 824pt body centred in 1024 canvas.
    let body = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * scale, yRadius: 185 * scale)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 18 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
    shadow.set()
    NSColor(white: 0.08, alpha: 1).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1), NSColor(srgbRed: 0.03, green: 0.03, blue: 0.05, alpha: 1)])!
        .draw(in: body, angle: -90)

    // Record.
    let center = NSPoint(x: s / 2, y: s / 2)
    let radius = 330 * scale
    let disc = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    NSGraphicsContext.saveGraphicsState()
    let discShadow = NSShadow()
    discShadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
    discShadow.shadowBlurRadius = 30 * scale
    discShadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
    discShadow.set()
    NSColor(white: 0.04, alpha: 1).setFill()
    disc.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Grooves.
    for i in 0..<22 {
        let r = radius - CGFloat(18 + i * 9) * scale
        guard r > 120 * scale else { break }
        let groove = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        groove.lineWidth = max(0.5, 1.6 * scale)
        NSColor(white: i % 3 == 0 ? 0.2 : 0.13, alpha: 1).setStroke()
        groove.stroke()
    }

    // Light sheen across the grooves.
    NSGraphicsContext.saveGraphicsState()
    disc.addClip()
    let sheen = NSBezierPath()
    sheen.move(to: center)
    sheen.appendArc(withCenter: center, radius: radius * 1.1, startAngle: 30, endAngle: 62)
    sheen.close()
    NSColor.white.withAlphaComponent(0.09).setFill()
    sheen.fill()
    let sheen2 = NSBezierPath()
    sheen2.move(to: center)
    sheen2.appendArc(withCenter: center, radius: radius * 1.1, startAngle: 210, endAngle: 242)
    sheen2.close()
    sheen2.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Label.
    let labelRadius = 118 * scale
    let label = NSBezierPath(ovalIn: NSRect(x: center.x - labelRadius, y: center.y - labelRadius, width: labelRadius * 2, height: labelRadius * 2))
    NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.62, blue: 1.0, alpha: 1), NSColor(srgbRed: 0.16, green: 0.42, blue: 0.95, alpha: 1)])!
        .draw(in: label, angle: -60)
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - labelRadius * 0.72, y: center.y - labelRadius * 0.72, width: labelRadius * 1.44, height: labelRadius * 1.44))
    ring.lineWidth = 3 * scale
    NSColor.white.withAlphaComponent(0.25).setStroke()
    ring.stroke()
    let holeRadius = 16 * scale
    NSColor(white: 0.06, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - holeRadius, y: center.y - holeRadius, width: holeRadius * 2, height: holeRadius * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()

    // Subtle top highlight on the squircle edge.
    let edge = NSBezierPath(roundedRect: body.insetBy(dx: 1 * scale, dy: 1 * scale), xRadius: 184 * scale, yRadius: 184 * scale)
    edge.lineWidth = 2 * scale
    NSColor.white.withAlphaComponent(0.08).setStroke()
    edge.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in sizes {
    try render(size: size).write(to: iconset.appendingPathComponent("\(name).png"))
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(process.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
