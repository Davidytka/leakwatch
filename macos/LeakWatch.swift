// LeakWatch - menu bar icon + desktop widget for macOS.
// Reads ~/.leakwatch/status.json (written by leakwatch.sh) and the log.
import AppKit

struct Entry: Decodable { let ip: String?; let country_name: String?; let asn: String?; let org: String? }
struct Status: Decodable {
    let time: String; let epoch: Double; let status: String; let message: String
    let ip: Entry?; let dns: [Entry]; let flagged: [String]
}

let dir = FileManager.default.homeDirectoryForCurrentUser.path + "/.leakwatch"
let statusPath = dir + "/status.json"
let logPath = dir + "/leakwatch.log"
let scriptPath = dir + "/leakwatch.sh"
let staleAfter: Double = 75 * 60   // no test for 75 min => "No recent test"

enum State {
    case ok, leak, critical, error, stale, testing, unknown
    var color: NSColor {
        switch self {
        case .ok: return .systemGreen
        case .leak, .error: return .systemOrange
        case .critical: return .systemRed
        case .testing: return .systemBlue
        case .stale, .unknown: return .systemGray
        }
    }
    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .leak, .critical, .error: return "xmark.circle.fill"
        case .testing: return "arrow.triangle.2.circlepath.circle.fill"
        case .stale, .unknown: return "clock.fill"
        }
    }
    /// Colored SF Symbol (white mark on a colored circle)
    func image(_ size: CGFloat) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white, color]))
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(cfg)
        img?.isTemplate = false
        return img
    }
    var title: String {
        switch self {
        case .ok: return "No leaks"
        case .leak: return "Leak: unwanted location"
        case .critical: return "Real location exposed"
        case .error: return "Test failed"
        case .stale: return "No recent test"
        case .testing: return "Testing…"
        case .unknown: return "No data yet"
        }
    }
}

/// Card background that drags its window (the rounded mask disables the default drag)
final class DragEffectView: NSVisualEffectView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var panel: NSPanel!
    var testing = false
    let defaults = UserDefaults.standard
    var showPanel: Bool {
        get { defaults.object(forKey: "showPanel") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showPanel") }
    }

    let dot = NSImageView()
    let headline = NSTextField(labelWithString: "")
    let sub = NSTextField(labelWithString: "")
    let details = NSTextField(wrappingLabelWithString: "")
    var runButton: NSButton!

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildPanel()
        refresh()
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
    }

    // MARK: data
    func load() -> Status? {
        guard let d = FileManager.default.contents(atPath: statusPath) else { return nil }
        return try? JSONDecoder().decode(Status.self, from: d)
    }

    func state(_ s: Status?) -> State {
        if testing { return .testing }
        guard let s = s else { return .unknown }
        switch s.status {
        case "CRITICAL": return .critical
        case "LEAK": return .leak
        case "ERROR": return .error
        default: break
        }
        return Date().timeIntervalSince1970 - s.epoch > staleAfter ? .stale : .ok
    }

    func ago(_ epoch: Double) -> String {
        let m = Int((Date().timeIntervalSince1970 - epoch) / 60)
        func plural(_ n: Int, _ w: String) -> String { "\(n) \(w)\(n == 1 ? "" : "s") ago" }
        if m < 1 { return "just now" }
        if m < 60 { return plural(m, "minute") }
        if m < 24 * 60 { return plural(m / 60, "hour") }
        return plural(m / (24 * 60), "day")
    }

    func short(_ e: Entry) -> String {
        let org = e.org ?? e.asn ?? ""
        return "\(e.country_name ?? "?")" + (org.isEmpty ? "" : " · \(org)")
    }

    func detailText(_ s: Status?) -> String {
        guard let s = s else { return "Waiting for the first test." }
        var lines: [String] = []
        if s.status == "ERROR" { lines.append(s.message) }
        if let ip = s.ip { lines.append("IP:  " + short(ip)) }
        var counts: [(String, Int)] = []
        for d in s.dns {
            let k = short(d)
            if let i = counts.firstIndex(where: { $0.0 == k }) { counts[i].1 += 1 } else { counts.append((k, 1)) }
        }
        for (k, c) in counts { lines.append("DNS: " + k + (c > 1 ? "  ×\(c)" : "")) }
        if !s.flagged.isEmpty { lines.append("Flagged:"); lines += s.flagged.map { "  " + $0 } }
        return lines.joined(separator: "\n")
    }

    /// Last n results from the log, newest first: (time, status)
    func history(_ n: Int) -> [(String, String)] {
        guard let text = try? String(contentsOfFile: logPath, encoding: .utf8) else { return [] }
        var out: [(String, String)] = []
        var cur: String? = nil
        for line in text.split(separator: "\n") {
            if line.hasPrefix("===== ") {
                cur = line.replacingOccurrences(of: "=", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("STATUS: "), let t = cur {
                let word = line.dropFirst(8).split(separator: " ").first.map(String.init) ?? "?"
                out.append((t, word)); cur = nil
            } else if line.hasPrefix("["), line.contains("ERROR"), let close = line.firstIndex(of: "]") {
                out.append((String(line[line.index(after: line.startIndex)..<close]), "ERROR"))
            }
        }
        return out.suffix(n).reversed().map { (t, s) in
            (t.count >= 16 ? String(t.dropFirst(5).prefix(11)) : t, s)   // "11-05 15:05"
        }
    }

    // MARK: UI
    func refresh() {
        let s = load()
        let st = state(s)
        let when = s.map { "Last test: \(ago($0.epoch))" } ?? ""

        item.button?.image = st.image(13)
        item.button?.imagePosition = .imageLeading
        item.button?.title = " DNS"
        item.button?.toolTip = "LeakWatch: \(st.title)"

        let menu = NSMenu()
        menu.autoenablesItems = false
        let head = NSMenuItem(title: st.title, action: nil, keyEquivalent: "")
        head.image = st.image(14)
        head.attributedTitle = NSAttributedString(string: st.title,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(head)
        if !when.isEmpty { menu.addItem(info(when)) }
        for l in detailText(s).split(separator: "\n") { menu.addItem(info(String(l))) }
        menu.addItem(.separator())
        menu.addItem(info("Recent tests:"))
        for (time, status) in history(6) {
            let hs: State = status == "OK" ? .ok : status == "CRITICAL" ? .critical : .leak
            let h = info("\(time)   \(status)")
            h.image = hs.image(11)
            menu.addItem(h)
        }
        menu.addItem(.separator())
        menu.addItem(action(testing ? "Testing…" : "Test now", #selector(runTest), "r", enabled: !testing))
        menu.addItem(action("Open log", #selector(openLog), "l"))
        menu.addItem(action("Edit settings", #selector(openConfig), ","))
        let p = action("Show desktop widget", #selector(togglePanel), "p")
        p.state = showPanel ? .on : .off
        menu.addItem(p)
        menu.addItem(.separator())
        menu.addItem(action("Quit LeakWatch", #selector(quit), "q"))
        item.menu = menu

        dot.image = st.image(20)
        headline.stringValue = st.title
        sub.stringValue = when
        details.stringValue = detailText(s)
        runButton.title = testing ? "Testing…" : "Test now"
        runButton.isEnabled = !testing
        if let v = panel.contentView { panel.setContentSize(NSSize(width: 290, height: v.fittingSize.height)) }
        if showPanel { panel.orderFront(nil) } else { panel.orderOut(nil) }
    }

    func info(_ s: String) -> NSMenuItem {
        let m = NSMenuItem(title: s, action: nil, keyEquivalent: ""); m.isEnabled = false; return m
    }
    func action(_ title: String, _ sel: Selector, _ key: String, enabled: Bool = true) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        m.target = self; m.isEnabled = enabled; return m
    }

    func buildPanel() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 290, height: 140),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // One level above desktop icons: Finder's desktop layer can't cover it and steal clicks,
        // but it stays below all normal windows
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false

        let bg = DragEffectView()
        bg.material = .hudWindow
        bg.state = .active
        // Rounded mask clips the blur itself, so no square background shows at the corners
        let r: CGFloat = 16
        let mask = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        mask.resizingMode = .stretch
        bg.maskImage = mask
        panel.contentView = bg

        dot.imageScaling = .scaleNone
        headline.font = .systemFont(ofSize: 17, weight: .semibold)
        headline.lineBreakMode = .byTruncatingTail
        headline.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        details.font = .systemFont(ofSize: 12)
        details.preferredMaxLayoutWidth = 258
        runButton = NSButton(title: "Test now", target: self, action: #selector(runTest))
        runButton.bezelStyle = .rounded
        runButton.controlSize = .small

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [dot, headline, spacer, runButton]); row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [row, sub, details])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bg.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
            bg.widthAnchor.constraint(equalToConstant: 290),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])

        if !panel.setFrameUsingName("LeakWatchWidget"), let sc = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: sc.maxX - 310, y: sc.maxY - 20))
        }
        panel.setFrameAutosaveName("LeakWatchWidget")
    }

    // MARK: actions
    @objc func runTest() {
        guard !testing else { return }
        testing = true
        refresh()
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [scriptPath]
            p.standardOutput = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async { self.testing = false; self.refresh() }
        }
    }
    @objc func openLog() { NSWorkspace.shared.open(URL(fileURLWithPath: logPath)) }
    @objc func openConfig() {
        NSWorkspace.shared.open([URL(fileURLWithPath: dir + "/config.sh")],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
            configuration: NSWorkspace.OpenConfiguration())
    }
    @objc func togglePanel() { showPanel.toggle(); refresh() }
    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
