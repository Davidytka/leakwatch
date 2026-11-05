// Renders assets/cover.png (1280x640 @2x) for the README and GitHub social preview.
// Run: swift assets/make-cover.swift
import AppKit

let W: CGFloat = 1280, H: CGFloat = 640, scale: CGFloat = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255,
            blue: CGFloat(h & 0xFF) / 255, alpha: a)
}
let green = rgb(0x34C759), red = rgb(0xFF3B30)

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0) {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
        .draw(at: NSPoint(x: x, y: y))
}
func symbol(_ name: String, _ size: CGFloat, _ color: NSColor, _ x: CGFloat, _ y: CGFloat) {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white, color]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
    img.draw(in: NSRect(x: x, y: y, width: img.size.width, height: img.size.height))
}
func glow(_ c: NSColor, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    // Soft radial glow that fades fully to transparent (no visible edge)
    let ctx = NSGraphicsContext.current!.cgContext
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [c.cgColor, c.withAlphaComponent(c.alphaComponent * 0.35).cgColor,
                                c.withAlphaComponent(0).cgColor] as CFArray,
                       locations: [0, 0.45, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                           endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}
func card(_ rect: NSRect, fill: NSColor) {
    let p = NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.45)
    sh.shadowBlurRadius = 40; sh.shadowOffset = NSSize(width: 0, height: -16); sh.set()
    fill.setFill(); p.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.08).setStroke(); p.lineWidth = 1; p.stroke()
}

// Background
NSGradient(colors: [rgb(0x070B14), rgb(0x0F1A30), rgb(0x16233F)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 35)
glow(green.withAlphaComponent(0.20), 940, 300, 520)
glow(rgb(0x3A6BFF, 0.20), 180, 620, 520)

// Subtle grid of dots
rgb(0xFFFFFF, 0.045).setFill()
for gx in stride(from: CGFloat(20), to: W, by: 32) {
    for gy in stride(from: CGFloat(20), to: H, by: 32) { NSBezierPath(ovalIn: NSRect(x: gx, y: gy, width: 2, height: 2)).fill() }
}

// Left: brand + pitch
symbol("checkmark.shield.fill", 46, green, 80, 466)
text("LeakWatch", 142, 456, .systemFont(ofSize: 64, weight: .heavy), .white, kern: -1.5)
text("Your VPN says you’re protected.", 80, 360, .systemFont(ofSize: 34, weight: .semibold), .white)
text("Your DNS might say otherwise.", 80, 316, .systemFont(ofSize: 34, weight: .semibold), green)
text("Hourly DNS leak checks · menu bar & tray icon", 80, 248, .systemFont(ofSize: 21, weight: .regular), rgb(0xFFFFFF, 0.62))
text("desktop widget · instant alerts", 80, 220, .systemFont(ofSize: 21, weight: .regular), rgb(0xFFFFFF, 0.62))

// Platform chips
var cx: CGFloat = 80
for label in ["macOS", "Windows", "Free & open source"] {
    let f = NSFont.systemFont(ofSize: 18, weight: .semibold)
    let w = (label as NSString).size(withAttributes: [.font: f]).width + 36
    let r = NSRect(x: cx, y: 120, width: w, height: 40)
    rgb(0xFFFFFF, 0.08).setFill(); NSBezierPath(roundedRect: r, xRadius: 20, yRadius: 20).fill()
    text(label, cx + 18, 129, f, rgb(0xFFFFFF, 0.85))
    cx += w + 12
}

// Right: alert card (behind) and OK card (front), like the real widget
card(NSRect(x: 790, y: 330, width: 410, height: 150), fill: rgb(0x2A1518, 0.96))
symbol("xmark.circle.fill", 30, red, 822, 427)
text("Real location exposed", 866, 428, .systemFont(ofSize: 26, weight: .semibold), .white)
text("DNS: your ISP · home country", 822, 384, .systemFont(ofSize: 19), rgb(0xFFFFFF, 0.6))

card(NSRect(x: 700, y: 150, width: 470, height: 230), fill: rgb(0x1E2638, 0.98))
symbol("checkmark.circle.fill", 34, green, 734, 316)
text("No leaks", 784, 316, .systemFont(ofSize: 32, weight: .semibold), .white)
let pill = NSRect(x: 1036, y: 318, width: 104, height: 36)
rgb(0xFFFFFF, 0.12).setFill(); NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10).fill()
text("Test now", 1052, 326, .systemFont(ofSize: 17, weight: .medium), .white)
text("Last test: 3 minutes ago", 736, 272, .systemFont(ofSize: 18), rgb(0xFFFFFF, 0.55))
text("IP:    Netherlands · VPN provider", 736, 226, .systemFont(ofSize: 20), rgb(0xFFFFFF, 0.88))
text("DNS: Sweden · Cloudflare  ×2", 736, 192, .systemFont(ofSize: 20), rgb(0xFFFFFF, 0.88))

// Menu bar pill
let mb = NSRect(x: 980, y: 540, width: 220, height: 46)
rgb(0xFFFFFF, 0.10).setFill(); NSBezierPath(roundedRect: mb, xRadius: 14, yRadius: 14).fill()
symbol("checkmark.circle.fill", 18, green, 1000, 553)
text("DNS", 1028, 552, .systemFont(ofSize: 19, weight: .semibold), .white)
symbol("wifi", 18, rgb(0xFFFFFF, 0.7), 1090, 554)
text("12:00", 1130, 552, .systemFont(ofSize: 19, weight: .medium), rgb(0xFFFFFF, 0.8))

NSGraphicsContext.current = nil
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/cover.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
