// Dipstick — menu bar readout of what your AI coding subscriptions have left.
//
// The app is deliberately thin: `dipstick --json` already knows how to read Codex
// rollout files, the Claude usage endpoint and agy's local RPC, so this process
// shells out to it rather than reimplementing three collectors in Swift. That
// keeps one source of truth and means the CLI, the web UI and the menu bar can
// never disagree about a number.

import AppKit
import SwiftUI
import UserNotifications

// MARK: - Snapshot decoded from `dipstick --json`

struct Snapshot: Decodable {
    let takenAt: String
    let main: String
    let subscriptions: [Subscription]
    let runningCodex: [Running]
    /// Optional so a snapshot from an older CLI still decodes.
    let mainMode: String?
    let barWindow: String?
    let nextLaunch: String?
    /// Rendered verbatim. The CLI already localises everything it prints, so the
    /// app borrows those strings instead of formatting its own -- otherwise a
    /// Korean reading ends up next to an English "resets in 1h 28m".
    let strings: [String: String]
}

struct Subscription: Decodable {
    let sub: String
    let key: String
    let account: String
    let isMain: Bool
    let selectable: Bool
    let reserve: Reserve?
    let windows: [Window]
    let note: String
}

struct Reserve: Decodable {
    let state: String
    let text: String
}

struct Window: Decodable {
    let name: String
    let pool: String?
    let remaining: Double
    let state: String
    let why: String
    let resetsAt: String?
    let resetsIn: String
    let imminent: Bool
    let binds: Bool
    let minutes: Double?
}

struct Running: Decodable {
    let home: String
    let count: Int
}

// MARK: - Status bar rendering

/// Menu bar space is scarce, so a subscription is shown by the part of its name
/// that distinguishes it from the others rather than its full label.
func shortName(_ sub: String) -> String {
    let words = sub.split(separator: " ")
    if sub.hasPrefix("Codex") { return String(words.last ?? "CODEX").uppercased() }
    if sub.hasPrefix("Claude") { return "CLAUDE" }
    if sub.hasPrefix("Antigravity") { return "AGY" }
    return String(words.first ?? "?").uppercased()
}

/// Draws one small column per subscription -- label above, reading below -- and
/// returns it as the status item image.
///
/// The menu bar is translucent, so whatever wallpaper is behind it shows through:
/// coloured text over a colourful desktop is unreadable, and a green figure on a
/// green wallpaper disappears entirely. Text is therefore drawn in the system
/// label colour, which macOS flips for a light or dark menu bar, and the state
/// rides on a small filled dot instead. Drawing to an image rather than hosting a
/// custom view keeps the normal button behaviour: one click still opens the menu.
func renderStatus(_ subs: [Subscription], pinned: Bool, prefer: String?, appearance: NSAppearance?) -> NSImage {
    // Three variants rendered side by side against the system readouts settled
    // this: the plain sans at semibold matches them exactly, where SF Mono's
    // mechanical glyphs read as heavier than they are and a condensed regular
    // label washes out. Digits stay monospaced so the figures do not twitch as
    // values change.
    let nameFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    let gap: CGFloat = 7, height: CGFloat = 22

    let pinFont = NSFont.systemFont(ofSize: 7.5, weight: .bold)
    let pinPadX: CGFloat = 4, pinGap: CGFloat = 4

    struct Column {
        let name: NSAttributedString
        let value: NSAttributedString
        let pin: NSAttributedString?
        let width: CGFloat
    }
    var columns: [Column] = []

    for sub in subs {
        guard let win = bindingWindow(sub, prefer: prefer) else { continue }
        // One figure per column. The dot and the countdown that used to sit here
        // made three things compete in 22 points; the panel has room for both.
        // Pinned mode means this one pool takes every launch; the label says so
        // right where the figure is read. The marker is a filled pill -- label
        // colour behind inverted text -- because a coloured word at 8pt washed
        // out against the translucent bar where a solid shape does not.
        let name = NSAttributedString(string: shortName(sub.sub), attributes: [
            .font: nameFont,
            .foregroundColor: NSColor.labelColor,
            .kern: 0.6])
        let pin: NSAttributedString? = (pinned && sub.isMain)
            ? NSAttributedString(string: "PIN", attributes: [
                .font: pinFont,
                .foregroundColor: NSColor.controlBackgroundColor,
                .kern: 0.5])
            : nil
        // Colour is reserved for trouble. TIGHT is still workable, so only LOW and
        // BLOCKED break monochrome -- a tint in the menu bar then always means
        // something needs attention rather than being decoration.
        let alarming = ["LOW", "BLOCKED"].contains(win.state)
        let tint = alarming ? colour(for: win.state) : NSColor.labelColor
        let value = NSAttributedString(
            string: "\(Int(win.remaining.rounded()))%",
            attributes: [.font: valueFont, .foregroundColor: tint])
        let nameBlock = name.size().width
            + (pin.map { $0.size().width + pinPadX * 2 + pinGap } ?? 0)
        columns.append(Column(name: name, value: value, pin: pin,
                              width: max(nameBlock, value.size().width)))
    }
    guard !columns.isEmpty else {
        let empty = NSImage(size: NSSize(width: 46, height: height))
        empty.lockFocus()
        NSAttributedString(string: "dipstick", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.7)])
            .draw(at: NSPoint(x: 0, y: 5))
        empty.unlockFocus()
        return empty
    }

    let total = columns.reduce(0) { $0 + $1.width } + gap * CGFloat(columns.count - 1)
    let image = NSImage(size: NSSize(width: ceil(total), height: height))
    let paint = {
        var x: CGFloat = 0
        for column in columns {
            let nameSize = column.name.size(), valueSize = column.value.size()
            // Positions come from the font metrics rather than tuned constants:
            // the label sits flush to the top of the bar and the figure's baseline
            // is pinned near the bottom, so raising the point size can never make
            // the two boxes collide.
            let nameY = height - nameSize.height
            let valueY = 2 - abs(valueFont.descender)
            let pinSize = column.pin?.size() ?? .zero
            let pillW = column.pin != nil ? pinSize.width + pinPadX * 2 : 0
            let block = nameSize.width + (column.pin != nil ? pinGap + pillW : 0)
            let nameX = x + (column.width - block) / 2
            column.name.draw(at: NSPoint(x: nameX, y: nameY))
            if let pin = column.pin {
                let pillH = pinSize.height + 1.5
                let pillRect = NSRect(x: nameX + nameSize.width + pinGap,
                                      y: nameY + (nameSize.height - pillH) / 2 - 0.5,
                                      width: pillW, height: pillH)
                NSColor.labelColor.setFill()
                NSBezierPath(roundedRect: pillRect, xRadius: pillH / 2, yRadius: pillH / 2).fill()
                pin.draw(at: NSPoint(x: pillRect.minX + pinPadX, y: pillRect.minY + 0.5))
            }
            column.value.draw(at: NSPoint(x: x + (column.width - valueSize.width) / 2, y: valueY))
            x += column.width + gap
        }
    }
    image.lockFocus()
    // resolve labelColor against the menu bar's appearance, not the app's
    if let appearance { appearance.performAsCurrentDrawingAppearance(paint) } else { paint() }
    image.unlockFocus()
    image.isTemplate = false        // a tinted figure must keep its colour
    return image
}

// MARK: - Presentation

/// Colours match the web UI so the two readouts never disagree at a glance.
func colour(for state: String) -> NSColor {
    switch state {
    case "GO": return NSColor.systemGreen
    case "TIGHT": return NSColor.systemYellow
    case "LOW": return NSColor.systemOrange
    case "BLOCKED": return NSColor.systemRed
    case "STALE": return NSColor.systemPurple
    default: return NSColor.secondaryLabelColor
    }
}

/// The window that actually constrains new work: the one `--json` marked as
/// binding, falling back to the lowest reading.
/// The window a column leads with. `prefer` pins one horizon so the figures stay
/// comparable across subscriptions; a subscription that has no window of that
/// length (Codex meters a 7-day window only) falls back to the constraining one
/// rather than dropping out of the bar entirely.
func bindingWindow(_ sub: Subscription, prefer: String? = nil) -> Window? {
    if let want = prefer, want != "binds" {
        let target: Double = (want == "5h") ? 300 : 10080
        let matches = sub.windows.filter { $0.minutes == target }
        // Account-wide before per-model: a Max plan carries both a 7-day window
        // and a 7-day Fable cap, and the plan's own figure is the headline.
        if let hit = matches.first(where: { $0.pool == nil }) ?? matches.first {
            return hit
        }
    }
    return sub.windows.first(where: { $0.binds }) ?? sub.windows.min(by: { $0.remaining < $1.remaining })
}

// MARK: - Running the CLI

enum CLI {
    /// Resolved once: a GUI app does not inherit the shell PATH, so the usual
    /// install locations are probed directly.
    static let path: String? = {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/dipstick",
            "/opt/homebrew/bin/dipstick",
            "/usr/local/bin/dipstick",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }()

    @discardableResult
    static func run(_ args: [String]) -> Data? {
        guard let path else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return task.terminationStatus == 0 ? data : nil
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let popover: NSPopover = {
        let p = NSPopover()
        p.behavior = .transient          // click away to dismiss, like a menu
        p.animates = false
        return p
    }()
    private var timer: Timer?
    var snapshot: Snapshot?
    var serverPort = 8787
    // Sync visibility: a refresh used to happen with no trace, so there was no
    // telling whether the numbers were fresh or the app was quietly stuck.
    var refreshing = false
    var lastSync: Date?
    var lastSyncFailed = false
    // Alerts fire on state *transitions*, never on repeated polls: the map of
    // last-seen states is the debounce. Empty until the first snapshot lands,
    // so launching the app into an already-low pool stays quiet -- the alert is
    // for the moment things change, not for the standing situation.
    var lastStates: [String: String] = [:]
    var alertsOn: Bool {
        get { UserDefaults.standard.object(forKey: "alerts") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "alerts") }
    }

    // `--snapshot <dir>`: render the status-bar image and the open panel to PNGs
    // and exit. The app can rasterise its own views without any screen-recording
    // or accessibility permission, which is exactly what a README screenshot
    // needs -- real pixels, real data, no TCC dialog.
    var snapshotDir: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 else { return nil }
        return args[i + 1]
    }()

    func applicationDidFinishLaunching(_ note: Notification) {
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        if alertsOn {
            UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        refresh()
        // Five minutes: the Claude endpoint rate-limits polling and the CLI caches
        // its response for the same interval, so anything faster only burns CPU.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc func refresh() {
        if refreshing { return }        // one in flight is enough
        refreshing = true
        repaint()
        // The status item dims while a sync runs -- visible even with the panel
        // closed, and it recovers on its own when the run finishes.
        item.button?.alphaValue = 0.5
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = CLI.run(["--json"])
            let snap = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                self.lastSyncFailed = (snap == nil)
                if let snap {
                    self.notifyTransitions(snap)
                    self.snapshot = snap    // a failed run keeps the last good numbers
                    self.lastSync = Date()
                }
                self.item.button?.alphaValue = 1
                self.repaint()
                if let dir = self.snapshotDir {
                    if self.snapshot == nil { fputs("dipstick: no snapshot data\n", stderr); exit(1) }
                    self.saveSnapshots(to: dir)
                }
            }
        }
    }

    /// Compare the constraining window per subscription against last poll and
    /// post an alert only when the state crosses in or out of trouble. STALE is
    /// excluded on both sides: an aged reading changing is not news.
    private func notifyTransitions(_ snap: Snapshot) {
        let strings = snap.strings ?? [:]
        var seen: [String: String] = [:]
        for sub in snap.subscriptions {
            guard let win = bindingWindow(sub) else { continue }
            let state = win.state
            seen[sub.sub] = state
            guard alertsOn, let prev = lastStates[sub.sub],
                  prev != state, prev != "STALE", state != "STALE" else { continue }
            let bad = ["LOW", "BLOCKED"]
            var title: String?
            var bodyKey: String?
            if bad.contains(state) && !bad.contains(prev) {
                title = strings[state == "BLOCKED" ? "notifBlockedTitle" : "notifLowTitle"]
                bodyKey = "notifLowBody"
            } else if bad.contains(prev) && !bad.contains(state) {
                title = strings["notifRecoveredTitle"]
                bodyKey = "notifRecoveredBody"
            }
            guard let title, let bodyKey else { continue }
            let body = (strings[bodyKey] ?? "{sub} {win} {pct}%")
                .replacingOccurrences(of: "{sub}", with: sub.sub)
                .replacingOccurrences(of: "{win}", with: win.name)
                .replacingOccurrences(of: "{pct}", with: String(Int(win.remaining.rounded())))
                .replacingOccurrences(of: "{reset}", with: win.resetsIn)
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            // One identifier per subscription: a newer alert replaces a stale
            // one instead of stacking a history nobody asked for.
            let req = UNNotificationRequest(
                identifier: "dipstick-\(sub.sub)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        }
        lastStates = seen
    }

    private func repaint() {
        updateTitle()
        if popover.isShown {
            popover.contentViewController?.view = makePanel()
        }
    }

    /// Main first, then whatever is tightest: the readings most likely to stop
    /// work. Every subscription with a reading gets a column — a fourth one
    /// costs ~35pt, and the cap of three silently hid Claude, which is exactly
    /// the pool whose floor matters most here.
    func orderedSubs(_ snap: Snapshot) -> [Subscription] {
        let bar = snap.barWindow
        let withData = snap.subscriptions.filter { !$0.windows.isEmpty }
        return withData.filter(\.isMain)
            + withData.filter { !$0.isMain }
                .sorted { (bindingWindow($0, prefer: bar)?.remaining ?? 101)
                            < (bindingWindow($1, prefer: bar)?.remaining ?? 101) }
    }

    private func updateTitle() {
        guard let button = item.button else { return }
        guard let snap = snapshot else {
            button.image = nil
            button.title = "dipstick ?"
            button.toolTip = CLI.path == nil
                ? "dipstick CLI not found in ~/.local/bin or Homebrew"
                : "Could not read a snapshot"
            return
        }
        let bar = snap.barWindow
        let ordered = orderedSubs(snap)
        button.title = ""
        button.image = renderStatus(ordered, pinned: snap.mainMode == "pinned",
                                    prefer: bar, appearance: button.effectiveAppearance)
        button.toolTip = ordered.compactMap { sub in
            bindingWindow(sub, prefer: bar).map { "\(sub.sub) · \($0.name) \(Int($0.remaining.rounded()))% · \($0.why)" }
        }.joined(separator: "\n")
    }

    // MARK: menu actions

    @objc func openDashboard() {
        // A live page when one is already being served, a written file otherwise.
        // Spawning a server to read a page left a process running for the rest of
        // the session, which is a lot of machinery for a detail view -- and the
        // fixed wait before opening the URL raced the bind often enough to land
        // on a connection error. The file needs nothing running at all.
        if portIsOpen(serverPort),
           let url = URL(string: "http://127.0.0.1:\(serverPort)/") {
            NSWorkspace.shared.open(url)
            return
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("dipstick-dashboard.html")
        guard CLI.run(["--html", out.path]) != nil,
              FileManager.default.fileExists(atPath: out.path) else { return }
        NSWorkspace.shared.open(out)
    }

    private func portIsOpen(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        return ok
    }

}

// MARK: - Snapshot rendering (`--snapshot <dir>`)

extension AppDelegate {
    /// Writes bar.png (the status-item image) and panel.png (the open panel) at
    /// 2x, both under the dark appearance so the pair composites into one hero
    /// image regardless of the machine's current theme.
    func saveSnapshots(to dir: String) {
        let dark = NSAppearance(named: .darkAqua)
        guard let raw = snapshot else { exit(1) }
        // A README screenshot is public: real account addresses are swapped for
        // example ones before anything is rendered.
        let stand = ["you@example.com", "work@example.com", "team@example.com"]
        var seen: [String: String] = [:]
        let snap = Snapshot(
            takenAt: raw.takenAt, main: raw.main,
            subscriptions: raw.subscriptions.map { s in
                let masked = seen[s.account] ?? stand[min(seen.count, stand.count - 1)]
                seen[s.account] = masked
                return Subscription(sub: s.sub, key: s.key, account: masked,
                                    isMain: s.isMain, selectable: s.selectable,
                                    reserve: s.reserve, windows: s.windows, note: s.note)
            },
            runningCodex: raw.runningCodex, mainMode: raw.mainMode,
            barWindow: raw.barWindow, nextLaunch: raw.nextLaunch, strings: raw.strings)
        snapshot = snap
        defer { snapshot = raw }
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        let out = URL(fileURLWithPath: dir)

        let barImage = renderStatus(orderedSubs(snap), pinned: snap.mainMode == "pinned",
                                    prefer: snap.barWindow, appearance: dark)
        writePNG(barImage, scale: 2, to: out.appendingPathComponent("bar.png"))

        // The panel view renders offscreen inside a borderless window: SwiftUI
        // needs a window to lay out, and the window supplies the 2x backing.
        let hosting = makePanel()
        let win = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000),
                                               size: hosting.frame.size),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.appearance = dark
        win.isOpaque = true
        win.backgroundColor = .windowBackgroundColor
        win.contentView = hosting
        win.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        // One runloop beat so SwiftUI finishes its first layout pass.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(1) }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: out.appendingPathComponent("panel.png"))
            exit(0)
        }
    }

    private func writePNG(_ image: NSImage, scale: CGFloat, to url: URL) {
        let w = Int(image.size.width * scale), h = Int(image.size.height * scale)
        guard w > 0, h > 0, let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

// MARK: - Popover

extension AppDelegate {
    func makePanel() -> NSView {
        let view = PanelView(
            snapshot: snapshot,
            cliMissing: CLI.path == nil,
            refreshing: refreshing,
            lastSync: lastSync,
            lastSyncFailed: lastSyncFailed,
            onPick: { [weak self] key in
                CLI.run(["--set-main", key])
                self?.refresh()
            },
            onMode: { [weak self] mode in
                CLI.run(["--main-mode", mode])
                self?.refresh()
            },
            onBarWindow: { [weak self] w in
                CLI.run(["--bar-window", w])
                self?.refresh()
            },
            onDashboard: { [weak self] in self?.openDashboard() },
            alertsOn: alertsOn,
            onAlerts: { [weak self] on in
                guard let self else { return }
                self.alertsOn = on
                if on {
                    UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }
                self.repaint()
            },
            onRefresh: { [weak self] in self?.refresh() },
            onQuit: { NSApp.terminate(nil) })
        let hosting = NSHostingView(rootView: view)
        // NSHostingView does not size a popover for you: without this the panel
        // is clipped to the popover's default height.
        hosting.frame.size = hosting.fittingSize
        popover.contentSize = hosting.fittingSize
        return hosting
    }

    @objc func togglePanel() {
        if popover.isShown { return popover.performClose(nil) }
        guard let button = item.button else { return }
        popover.contentViewController = {
            let controller = NSViewController()
            controller.view = makePanel()
            return controller
        }()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        refresh()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
