// Dipstick — menu bar readout of what your AI coding subscriptions have left.
//
// The app is deliberately thin: `dipstick --json` already knows how to read Codex
// rollout files, the Claude usage endpoint and agy's local RPC, so this process
// shells out to it rather than reimplementing three collectors in Swift. That
// keeps one source of truth and means the CLI, the web UI and the menu bar can
// never disagree about a number.

import AppKit

// MARK: - Snapshot decoded from `dipstick --json`

struct Snapshot: Decodable {
    let takenAt: String
    let main: String
    let subscriptions: [Subscription]
    let runningCodex: [Running]
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
/// returns it as the status item image. Drawing to an image rather than hosting a
/// custom view keeps the normal button behaviour: one click still opens the menu.
func renderStatus(_ subs: [Subscription]) -> NSImage {
    let nameFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
    let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
    let tailFont = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium)
    let gap: CGFloat = 9, height: CGFloat = 22

    struct Column { let name: NSAttributedString; let value: NSAttributedString; let width: CGFloat }
    var columns: [Column] = []

    for sub in subs {
        guard let win = bindingWindow(sub) else { continue }
        let name = NSAttributedString(string: shortName(sub.sub), attributes: [
            .font: nameFont, .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.4])
        let value = NSMutableAttributedString(
            string: "\(Int(win.remaining.rounded()))%",
            attributes: [.font: valueFont, .foregroundColor: colour(for: win.state)])
        if !win.resetsIn.isEmpty {
            // just the magnitude: "2시간 47분 후" is too wide for a menu bar
            let compact = win.resetsIn
                .replacingOccurrences(of: " 후", with: "")
                .replacingOccurrences(of: "in ", with: "")
                .split(separator: " ").first.map(String.init) ?? ""
            if !compact.isEmpty {
                value.append(NSAttributedString(string: " " + compact, attributes: [
                    .font: tailFont, .foregroundColor: NSColor.tertiaryLabelColor]))
            }
        }
        columns.append(Column(name: name, value: value,
                              width: max(name.size().width, value.size().width)))
    }
    guard !columns.isEmpty else {
        let empty = NSImage(size: NSSize(width: 44, height: height))
        empty.lockFocus()
        NSAttributedString(string: "dipstick", attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor])
            .draw(at: NSPoint(x: 0, y: 6))
        empty.unlockFocus()
        return empty
    }

    let total = columns.reduce(0) { $0 + $1.width } + gap * CGFloat(columns.count - 1)
    let image = NSImage(size: NSSize(width: ceil(total), height: height))
    image.lockFocus()
    var x: CGFloat = 0
    for column in columns {
        let nameX = x + (column.width - column.name.size().width) / 2
        let valueX = x + (column.width - column.value.size().width) / 2
        column.name.draw(at: NSPoint(x: nameX, y: 12))
        column.value.draw(at: NSPoint(x: valueX, y: 1))
        x += column.width + gap
    }
    image.unlockFocus()
    image.isTemplate = false        // the state colours must survive
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
func bindingWindow(_ sub: Subscription) -> Window? {
    sub.windows.first(where: { $0.binds }) ?? sub.windows.min(by: { $0.remaining < $1.remaining })
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
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var snapshot: Snapshot?
    private var serverPort = 8787

    func applicationDidFinishLaunching(_ note: Notification) {
        item.menu = NSMenu()
        item.menu?.delegate = self
        refresh()
        // Five minutes: the Claude endpoint rate-limits polling and the CLI caches
        // its response for the same interval, so anything faster only burns CPU.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = CLI.run(["--json"])
            let snap = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
            DispatchQueue.main.async {
                self?.snapshot = snap
                self?.updateTitle()
            }
        }
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
        // Main first, then whatever is tightest: the readings most likely to stop
        // work. Everything else is one click away in the menu.
        let withData = snap.subscriptions.filter { !$0.windows.isEmpty }
        let ordered = withData.filter(\.isMain)
            + withData.filter { !$0.isMain }
                .sorted { (bindingWindow($0)?.remaining ?? 101) < (bindingWindow($1)?.remaining ?? 101) }
        button.title = ""
        button.image = renderStatus(Array(ordered.prefix(3)))
        button.toolTip = ordered.compactMap { sub in
            bindingWindow(sub).map { "\(sub.sub) · \($0.name) \(Int($0.remaining.rounded()))% · \($0.why)" }
        }.joined(separator: "\n")
    }

    // MARK: menu actions

    @objc private func setMain(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        CLI.run(["--set-main", key])
        refresh()
    }

    @objc private func openDashboard() {
        guard let url = URL(string: "http://127.0.0.1:\(serverPort)/") else { return }
        // Start a server only if nothing answers; --serve is meant to be on demand.
        if !portIsOpen(serverPort), let path = CLI.path {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = ["--serve", String(serverPort)]
            try? task.run()
            Thread.sleep(forTimeInterval: 1.2)
        }
        NSWorkspace.shared.open(url)
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

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Menu

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        guard let snap = snapshot else {
            let why = CLI.path == nil
                ? "dipstick CLI not found — install it to ~/.local/bin"
                : "No reading yet"
            menu.addItem(disabled(why))
            menu.addItem(.separator())
            menu.addItem(action("Refresh now", #selector(refresh)))
            menu.addItem(action("Quit", #selector(quit)))
            return
        }

        for sub in snap.subscriptions {
            let header = NSMenuItem()
            header.attributedTitle = headerLine(sub)
            menu.addItem(header)

            for win in sub.windows {
                menu.addItem(windowRow(win))
            }
            if let reserve = sub.reserve, reserve.state != "GO" {
                menu.addItem(noteRow("⚠ " + reserve.text, colour(for: reserve.state)))
            }
            if !sub.note.isEmpty { menu.addItem(noteRow(sub.note, .tertiaryLabelColor)) }

            if sub.selectable {
                let label = sub.isMain ? str("unsetMain", "Unset as main")
                                       : str("setAsMain", "Set as main")
                let pick = action("   " + label, #selector(setMain(_:)))
                pick.representedObject = sub.isMain ? "auto" : sub.key
                menu.addItem(pick)
            }
            menu.addItem(.separator())
        }

        let running = snap.runningCodex.reduce(0) { $0 + $1.count }
        if running > 0 {
            menu.addItem(noteRow(str("running", "{n} codex running")
                .replacingOccurrences(of: "{n}", with: String(running)), .tertiaryLabelColor))
        }
        menu.addItem(noteRow(str("updated", "updated {t}")
            .replacingOccurrences(of: "{t}", with: String(snap.takenAt.suffix(8))),
            .tertiaryLabelColor))
        menu.addItem(.separator())
        menu.addItem(action(str("openDashboard", "Open dashboard…"), #selector(openDashboard)))
        menu.addItem(action(str("refresh", "Refresh now"), #selector(refresh)))
        menu.addItem(action(str("quit", "Quit Dipstick"), #selector(quit)))
    }

    private func str(_ key: String, _ fallback: String) -> String {
        snapshot?.strings[key] ?? fallback
    }

    /// One window: a colour-coded dot, the window name, then the figure and the
    /// recovery time on their own tab stops so the columns line up down the menu.
    /// The dot carries the state as colour, the row still reads without it --
    /// colour is never the only signal.
    private func windowRow(_ win: Window) -> NSMenuItem {
        let tint = colour(for: win.state)
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 168),
                              NSTextTab(textAlignment: .left, location: 180)]

        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: "   ● ", attributes: [
            .foregroundColor: tint,
            .font: NSFont.systemFont(ofSize: 9)]))
        let title = [win.pool, win.name].compactMap { $0 }.joined(separator: " · ")
        line.append(NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 12)]))
        line.append(NSAttributedString(string: "\t\(Int(win.remaining.rounded()))%", attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)]))
        var tail = win.resetsIn
        if win.binds { tail += "  " + str("binds", "binds") }
        else if win.imminent { tail += "  " + str("recovering", "recovering") }
        line.append(NSAttributedString(string: "\t" + tail, attributes: [
            .foregroundColor: win.binds ? tint : NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 11, weight: win.binds ? .semibold : .regular)]))
        line.addAttribute(.paragraphStyle, value: paragraph,
                          range: NSRange(location: 0, length: line.length))

        let entry = NSMenuItem()
        entry.attributedTitle = line
        entry.isEnabled = false
        return entry
    }

    private func noteRow(_ text: String, _ tint: NSColor) -> NSMenuItem {
        let entry = NSMenuItem()
        entry.attributedTitle = NSAttributedString(string: "   " + text, attributes: [
            .foregroundColor: tint, .font: NSFont.systemFont(ofSize: 11)])
        entry.isEnabled = false
        return entry
    }

    private func headerLine(_ sub: Subscription) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: sub.sub,
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold),
                         .foregroundColor: NSColor.labelColor])
        if sub.isMain {
            title.append(NSAttributedString(
                string: "  MAIN",
                attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .heavy),
                             .foregroundColor: NSColor.controlAccentColor,
                             .kern: 0.6]))
        }
        title.append(NSAttributedString(
            string: "   \(sub.account)",
            attributes: [.font: NSFont.systemFont(ofSize: 10),
                         .foregroundColor: NSColor.tertiaryLabelColor]))
        return title
    }

    private func disabled(_ text: String) -> NSMenuItem {
        let entry = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        entry.target = self
        return entry
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
