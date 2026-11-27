// Renders Resources/AppIcon.icns (a black vinyl record on an accent-blue squircle).
// The bright background keeps the icon visible against dark Docks and taskbars.
// Usage: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Disque-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}

func circle(_ center: NSPoint, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    let scale = s / 1024

    // macOS icon grid: 824pt body centred in 1024 canvas.
    let body = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * scale, yRadius: 185 * scale)
    let backgroundTop = srgb(0.35, 0.64, 1.0)
    let backgroundBottom = srgb(0.10, 0.36, 0.92)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 18 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
    shadow.set()
    backgroundBottom.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [backgroundTop, backgroundBottom])!.draw(in: body, angle: -90)
    // Soft glow from the top-left.
    let glowCenter = NSPoint(x: 300 * scale, y: 860 * scale)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: 620 * scale, options: [])

    // Record.
    let center = NSPoint(x: s / 2, y: s / 2)
    let radius = 352 * scale
    let labelRadius = 122 * scale
    let disc = circle(center, radius)
    NSGraphicsContext.saveGraphicsState()
    let discShadow = NSShadow()
    discShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    discShadow.shadowBlurRadius = 34 * scale
    discShadow.shadowOffset = NSSize(width: 0, height: -16 * scale)
    discShadow.set()
    NSColor(white: 0.06, alpha: 1).setFill()
    disc.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Grooves.
    for i in 0... {
        let r = radius - CGFloat(20 + i * 10) * scale
        guard r > labelRadius + 14 * scale else { break }
        let groove = circle(center, r)
        groove.lineWidth = max(0.5, 1.8 * scale)
        NSColor(white: i % 3 == 0 ? 0.22 : 0.14, alpha: 1).setStroke()
        groove.stroke()
    }

    // Light sheen across the grooves.
    NSGraphicsContext.saveGraphicsState()
    disc.addClip()
    NSColor.white.withAlphaComponent(0.12).setFill()
    for (start, end) in [(28.0, 64.0), (208.0, 244.0)] {
        let sheen = NSBezierPath()
        sheen.move(to: center)
        sheen.appendArc(withCenter: center, radius: radius * 1.1, startAngle: start, endAngle: end)
        sheen.close()
        sheen.fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    // Faint rim so the record's edge separates from its shadow.
    let rim = circle(center, radius - 2 * scale)
    rim.lineWidth = 3 * scale
    NSColor.white.withAlphaComponent(0.14).setStroke()
    rim.stroke()

    // Label.
    let label = circle(center, labelRadius)
    NSGradient(colors: [NSColor.white, srgb(0.86, 0.90, 0.97)])!.draw(in: label, angle: -60)
    let ring = circle(center, labelRadius * 0.72)
    ring.lineWidth = 3 * scale
    NSColor.black.withAlphaComponent(0.12).setStroke()
    ring.stroke()
    NSColor(white: 0.06, alpha: 1).setFill()
    circle(center, 17 * scale).fill()

    NSGraphicsContext.restoreGraphicsState()

    // Highlight along the squircle edge.
    let edge = NSBezierPath(roundedRect: body.insetBy(dx: 1.5 * scale, dy: 1.5 * scale), xRadius: 184 * scale, yRadius: 184 * scale)
    edge.lineWidth = 3 * scale
    NSColor.white.withAlphaComponent(0.25).setStroke()
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
