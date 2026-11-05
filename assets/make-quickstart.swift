// Renders the "Quick start" README art:
//   quickstart-ru.png / quickstart-en.png  (vertical, 3 steps)
//   icon-macos.png / icon-windows.png      (platform badges for headings)
// Build & run: swiftc -o /tmp/makeqs assets/make-quickstart.swift && /tmp/makeqs assets
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets"

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255,
            blue: CGFloat(h & 0xFF) / 255, alpha: a)
}
let green = rgb(0x34C759)

func render(_ name: String, _ w: CGFloat, _ h: CGFloat, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * 2), pixelsHigh: Int(h * 2),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("Wrote \(outDir)/\(name)")
}

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ font: NSFont, _ color: NSColor) {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color]).draw(at: NSPoint(x: x, y: y))
}
func symbol(_ name: String, _ size: CGFloat, _ colors: [NSColor], _ x: CGFloat, _ y: CGFloat, weight: NSFont.Weight = .semibold) {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: colors))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
    img.draw(in: NSRect(x: x - img.size.width / 2, y: y - img.size.height / 2, width: img.size.width, height: img.size.height))
}
func glow(_ c: NSColor, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [c.cgColor, c.withAlphaComponent(c.alphaComponent * 0.35).cgColor,
                                c.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.45, 1])!
    NSGraphicsContext.current!.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0,
        endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}
func roundedBackground(_ rect: NSRect, _ radius: CGFloat) {
    let p = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    p.addClip()
    NSGradient(colors: [rgb(0x070B14), rgb(0x0F1A30), rgb(0x16233F)])!.draw(in: rect, angle: 60)
    glow(rgb(0x3A6BFF, 0.22), rect.minX + rect.width * 0.2, rect.maxY - 40, rect.width * 0.8)
    glow(green.withAlphaComponent(0.16), rect.maxX - 40, rect.minY + 80, rect.width * 0.8)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.08).setStroke(); p.lineWidth = 1; p.stroke()
}

// ---- vertical Quick start card ----
struct Step { let icon: String; let title: String; let sub: String }

func quickstart(_ lang: String) {
    let ru = lang == "ru"
    let W: CGFloat = 520, H: CGFloat = 800
    let steps = ru ? [
        Step(icon: "lock.shield.fill", title: "Подключи VPN", sub: "любой, как обычно"),
        Step(icon: "terminal.fill", title: "Вставь одну команду", sub: "Терминал или PowerShell"),
        Step(icon: "checkmark.circle.fill", title: "Готово", sub: "✓ в меню и виджет на столе"),
    ] : [
        Step(icon: "lock.shield.fill", title: "Connect your VPN", sub: "any VPN, as usual"),
        Step(icon: "terminal.fill", title: "Paste one command", sub: "Terminal or PowerShell"),
        Step(icon: "checkmark.circle.fill", title: "Done", sub: "✓ in the menu bar + widget"),
    ]
    render("quickstart-\(lang).png", W, H) {
        roundedBackground(NSRect(x: 0, y: 0, width: W, height: H), 36)

        // Header
        symbol("bolt.fill", 34, [rgb(0xFFD60A)], 64, H - 78)
        text(ru ? "Быстрый запуск" : "Quick start", 94, H - 100, .systemFont(ofSize: 38, weight: .heavy), .white)
        text(ru ? "3 шага · около минуты" : "3 steps · about a minute", 48, H - 148,
             .systemFont(ofSize: 21, weight: .medium), rgb(0xFFFFFF, 0.55))

        // Steps
        let top = H - 200, stepH: CGFloat = 158, gap: CGFloat = 36
        for (i, s) in steps.enumerated() {
            let y = top - CGFloat(i + 1) * stepH - CGFloat(i) * gap
            let card = NSRect(x: 40, y: y, width: W - 80, height: stepH)
            let last = i == steps.count - 1
            (last ? rgb(0x163A2A, 0.95) : rgb(0xFFFFFF, 0.07)).setFill()
            NSBezierPath(roundedRect: card, xRadius: 24, yRadius: 24).fill()
            if last {
                green.withAlphaComponent(0.55).setStroke()
                let b = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 24, yRadius: 24)
                b.lineWidth = 1.5; b.stroke()
            }

            // number badge
            let bc = NSRect(x: card.minX + 24, y: card.maxY - 64, width: 40, height: 40)
            (last ? green : rgb(0xFFFFFF, 0.14)).setFill(); NSBezierPath(ovalIn: bc).fill()
            let num = "\(i + 1)" as NSString
            let nf = NSFont.systemFont(ofSize: 21, weight: .bold)
            let ns = num.size(withAttributes: [.font: nf])
            text("\(i + 1)", bc.midX - ns.width / 2, bc.midY - ns.height / 2, nf, .white)

            text(s.title, card.minX + 80, card.maxY - 62, .systemFont(ofSize: 27, weight: .semibold), .white)
            text(s.sub, card.minX + 80, card.maxY - 98, .systemFont(ofSize: 19), rgb(0xFFFFFF, 0.6))

            // big icon on the right
            symbol(s.icon, 34, last ? [.white, green] : [rgb(0xFFFFFF, 0.75), rgb(0xFFFFFF, 0.25)],
                   card.maxX - 50, card.midY, weight: .regular)

            // connector to the next step
            if !last {
                rgb(0xFFFFFF, 0.25).setStroke()
                let l = NSBezierPath()
                l.move(to: NSPoint(x: bc.midX, y: card.minY - 6))
                l.line(to: NSPoint(x: bc.midX, y: card.minY - gap + 6))
                l.lineWidth = 2; l.setLineDash([5, 5], count: 2, phase: 0); l.stroke()
            }
        }

        // mini command preview inside step 2
        let s2 = top - 2 * stepH - gap
        let cmd = NSRect(x: 120, y: s2 + 18, width: W - 240, height: 30)
        rgb(0x000000, 0.35).setFill(); NSBezierPath(roundedRect: cmd, xRadius: 8, yRadius: 8).fill()
        text("$ curl … | install.sh", cmd.minX + 12, cmd.minY + 5,
             .monospacedSystemFont(ofSize: 15, weight: .regular), green.withAlphaComponent(0.9))
    }
}

// ---- platform icons (rounded tile) ----
func icon(_ name: String, _ draw: (NSRect) -> Void) {
    let S: CGFloat = 128
    render(name, S, S) {
        let r = NSRect(x: 0, y: 0, width: S, height: S)
        roundedBackground(r, 30)
        draw(r)
    }
}

quickstart("ru")
quickstart("en")

icon("icon-macos.png") { r in
    symbol("apple.logo", 62, [.white], r.midX, r.midY + 3, weight: .regular)
}
icon("icon-windows.png") { r in
    // Four panes
    let s: CGFloat = 30, g: CGFloat = 5
    let x0 = r.midX - s - g / 2, y0 = r.midY - s - g / 2
    rgb(0x3FA9F5).setFill()
    for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
        NSBezierPath(roundedRect: NSRect(x: x0 + CGFloat(dx) * (s + g), y: y0 + CGFloat(dy) * (s + g), width: s, height: s),
                     xRadius: 3, yRadius: 3).fill()
    }
}
