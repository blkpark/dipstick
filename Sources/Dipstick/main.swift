// Dipstick — menu bar readout of what your AI coding subscriptions have left.
//
// The app is deliberately thin: `dipstick --json` already knows how to read Codex
// rollout files, the Claude usage endpoint and agy's local RPC, so this process
// shells out to it rather than reimplementing three collectors in Swift. That
// keeps one source of truth and means the CLI, the web UI and the menu bar can
// never disagree about a number.

import AppKit
import SwiftUI

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
/// returns it as the status item image.
///
/// The menu bar is translucent, so whatever wallpaper is behind it shows through:
/// coloured text over a colourful desktop is unreadable, and a green figure on a
/// green wallpaper disappears entirely. Text is therefore drawn in the system
/// label colour, which macOS flips for a light or dark menu bar, and the state
/// rides on a small filled dot instead. Drawing to an image rather than hosting a
/// custom view keeps the normal button behaviour: one click still opens the menu.
func renderStatus(_ subs: [Subscription], appearance: NSAppearance?) -> NSImage {
    // Condensed label, SF Mono figure. The condensed face buys menu bar width back
    // and the monospaced digits stop the readout jittering as values change --
    // together they read as instrumentation rather than as a sentence. Light
    // weights: bold text beside the system's own readouts looks like shouting.
    let nameFont = NSFont.systemFont(ofSize: 9, weight: .regular, width: .condensed)
    let valueFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    let gap: CGFloat = 11, height: CGFloat = 22

    struct Column { let name: NSAttributedString; let value: NSAttributedString; let width: CGFloat }
    var columns: [Column] = []

    for sub in subs {
        guard let win = bindingWindow(sub) else { continue }
        // One figure per column. The dot and the countdown that used to sit here
        // made three things compete in 22 points; the panel has room for both.
        let name = NSAttributedString(string: shortName(sub.sub), attributes: [
            .font: nameFont,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85),
            .kern: 0.6])
        // Colour is reserved for trouble. TIGHT is still workable, so only LOW and
        // BLOCKED break monochrome -- a tint in the menu bar then always means
        // something needs attention rather than being decoration.
        let alarming = ["LOW", "BLOCKED"].contains(win.state)
        let tint = alarming ? colour(for: win.state) : NSColor.labelColor
        let value = NSAttributedString(
            string: "\(Int(win.remaining.rounded()))%",
            attributes: [.font: valueFont, .foregroundColor: tint])
        columns.append(Column(name: name, value: value,
                              width: max(name.size().width, value.size().width)))
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
            column.name.draw(at: NSPoint(x: x + (column.width - nameSize.width) / 2, y: 11.5))
            column.value.draw(at: NSPoint(x: x + (column.width - valueSize.width) / 2, y: 0.5))
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

    func applicationDidFinishLaunching(_ note: Notification) {
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
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
                guard let self else { return }
                self.snapshot = snap
                self.updateTitle()
                if self.popover.isShown {
                    self.popover.contentViewController?.view = self.makePanel()
                }
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
        button.image = renderStatus(Array(ordered.prefix(3)),
                                    appearance: button.effectiveAppearance)
        button.toolTip = ordered.compactMap { sub in
            bindingWindow(sub).map { "\(sub.sub) · \($0.name) \(Int($0.remaining.rounded()))% · \($0.why)" }
        }.joined(separator: "\n")
    }

    // MARK: menu actions

    @objc func openDashboard() {
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

}

// MARK: - Popover

extension AppDelegate {
    func makePanel() -> NSView {
        let view = PanelView(
            snapshot: snapshot,
            cliMissing: CLI.path == nil,
            onPick: { [weak self] key in
                CLI.run(["--set-main", key])
                self?.refresh()
            },
            onDashboard: { [weak self] in self?.openDashboard() },
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
