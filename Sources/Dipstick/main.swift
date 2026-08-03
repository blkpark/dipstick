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
    let imminent: Bool
    let binds: Bool
}

struct Running: Decodable {
    let home: String
    let count: Int
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

func shortTime(_ iso: String?) -> String {
    guard let iso, let date = parseTimestamp(iso) else { return "" }
    let secs = date.timeIntervalSinceNow
    if secs < 0 { return "due" }
    let mins = Int(secs / 60)
    if mins < 60 { return "\(mins)m" }
    let (h, m) = (mins / 60, mins % 60)
    if h < 24 { return m == 0 ? "\(h)h" : "\(h)h \(m)m" }
    return "\(h / 24)d \(h % 24)h"
}

private let isoParser: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let localParser: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    f.timeZone = .current
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

/// `--json` emits local time with no zone designator, which the strict ISO parser
/// rejects, so fall back to a plain local formatter before giving up.
func parseTimestamp(_ string: String) -> Date? {
    isoParser.date(from: string) ?? localParser.date(from: String(string.prefix(19)))
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
            button.title = "dipstick ?"
            button.toolTip = CLI.path == nil
                ? "dipstick CLI not found in ~/.local/bin or Homebrew"
                : "Could not read a snapshot"
            return
        }
        // Show the main subscription if one is set, else whatever is tightest --
        // the number most likely to stop work either way.
        let shown = snap.subscriptions.first(where: { $0.isMain })
            ?? snap.subscriptions.min(by: {
                (bindingWindow($0)?.remaining ?? 101) < (bindingWindow($1)?.remaining ?? 101)
            })
        guard let shown, let win = bindingWindow(shown) else {
            button.title = "dipstick"
            return
        }
        let text = "\(Int(win.remaining.rounded()))%"
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: colour(for: win.state),
                         .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)])
        button.toolTip = "\(shown.sub) · \(win.name) · \(win.why)"
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
                let bits = [win.pool, win.name].compactMap { $0 }.joined(separator: " · ")
                let mark = win.binds ? " ◂ binds" : (win.imminent ? " ◂ recovering" : "")
                let reset = shortTime(win.resetsAt)
                let line = "    \(bits)  \(Int(win.remaining.rounded()))%"
                    + (reset.isEmpty ? "" : "  ·  resets in \(reset)") + mark
                let entry = disabled(line)
                entry.attributedTitle = NSAttributedString(
                    string: line,
                    attributes: [.foregroundColor: colour(for: win.state),
                                 .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)])
                menu.addItem(entry)
            }
            if let reserve = sub.reserve, reserve.state != "GO" {
                menu.addItem(disabled("    ⚠ \(reserve.text)"))
            }
            if !sub.note.isEmpty { menu.addItem(disabled("    \(sub.note)")) }

            if sub.selectable {
                let title = sub.isMain ? "    Unset as main" : "    Set as main"
                let pick = action(title, #selector(setMain(_:)))
                pick.representedObject = sub.isMain ? "auto" : sub.key
                menu.addItem(pick)
            }
            menu.addItem(.separator())
        }

        let running = snap.runningCodex.reduce(0) { $0 + $1.count }
        if running > 0 { menu.addItem(disabled("\(running) codex processes running")) }
        menu.addItem(disabled("Updated \(String(snap.takenAt.suffix(8)))"))
        menu.addItem(.separator())
        menu.addItem(action("Open dashboard…", #selector(openDashboard)))
        menu.addItem(action("Refresh now", #selector(refresh)))
        menu.addItem(action("Quit Dipstick", #selector(quit)))
    }

    private func headerLine(_ sub: Subscription) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: sub.sub,
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        if sub.isMain {
            title.append(NSAttributedString(
                string: "  MAIN",
                attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .bold),
                             .foregroundColor: NSColor.controlAccentColor]))
        }
        title.append(NSAttributedString(
            string: "  \(sub.account)",
            attributes: [.font: NSFont.systemFont(ofSize: 10),
                         .foregroundColor: NSColor.secondaryLabelColor]))
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
