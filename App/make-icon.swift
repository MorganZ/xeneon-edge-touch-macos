// Generates App/AppIcon.icns: a macOS squircle with a wide Xeneon-style screen
// and a tapping hand. Run via `make icon` (needs only the Xcode CLT).
import AppKit

func render(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size / 1024
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: the squircle occupies ~82% of the canvas.
    let inset = 100 * s
    let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: 185 * s, yRadius: 185 * s)

    // Shadow + background gradient (deep blue-black -> Corsair-ish charcoal)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 30 * s, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor.black.setFill(); squircle.fill()
    ctx.restoreGState()
    squircle.addClip()
    NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.20, alpha: 1),
                        NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.07, alpha: 1)])!
        .draw(in: rect, angle: -90)

    // Wide 32:9 screen bar, glowing yellow (Corsair accent)
    let screen = CGRect(x: rect.minX + 110 * s, y: rect.midY - 40 * s, width: rect.width - 220 * s, height: 190 * s)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: 28 * s, yRadius: 28 * s)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60 * s, color: NSColor(calibratedRed: 1, green: 0.8, blue: 0.1, alpha: 0.7).cgColor)
    NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.16, alpha: 1).setFill(); screenPath.fill()
    ctx.restoreGState()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)])!
        .draw(in: screenPath, angle: -90)

    // Touch ripple where the finger lands
    let touch = CGPoint(x: screen.midX + 120 * s, y: screen.midY)
    for (r, a) in [(150.0, 0.18), (95.0, 0.35)] {
        NSColor.white.withAlphaComponent(a).setStroke()
        let ring = NSBezierPath(ovalIn: CGRect(x: touch.x - r * s, y: touch.y - r * s, width: 2 * r * s, height: 2 * r * s))
        ring.lineWidth = 14 * s; ring.stroke()
    }

    // Hand: SF Symbol "hand.point.up.left.fill", rendered white with a soft shadow
    let cfg = NSImage.SymbolConfiguration(pointSize: 440 * s, weight: .medium)
    if let hand = NSImage(systemSymbolName: "hand.point.up.left.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: hand.size, flipped: false) { r in
            NSColor.white.set(); r.fill()
            hand.draw(in: r, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 24 * s, color: NSColor.black.withAlphaComponent(0.6).cgColor)
        let hs = hand.size
        tinted.draw(in: CGRect(x: touch.x - hs.width * 0.30, y: touch.y - hs.height * 0.86, width: hs.width, height: hs.height))
        ctx.restoreGState()
    }

    img.unlockFocus()
    return img
}

func png(_ img: NSImage, _ px: Int, _ path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: CGRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]  // iconset directory
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let master = render(1024)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                   ("512x512", 512), ("512x512@2x", 1024)] {
    png(master, px, "\(out)/icon_\(name).png")
}
