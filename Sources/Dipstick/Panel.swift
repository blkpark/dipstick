// The dropdown panel.
//
// This is a popover with a SwiftUI view rather than an NSMenu. A menu fixes the
// font, the row height and the layout, so the readings could only ever be a list
// of sentences; a panel can put a label on the left and its figure on the right,
// align the columns, and group things under quiet section headings.

import SwiftUI

// MARK: - Type scale
//
// Four sizes only. Hierarchy comes from weight and colour, not from a new size
// per element -- that is what made the earlier menu read as noise.

extension Font {
    static let dsSection = Font.system(size: 9.5, weight: .medium).width(.expanded)
    static let dsLabel = Font.system(size: 12)
    /// SF Mono for every figure: fixed advance widths keep the percentage and the
    /// recovery columns from shifting as the numbers change.
    static let dsValue = Font.system(size: 11.5, weight: .regular, design: .monospaced)
    static let dsTitle = Font.system(size: 13, weight: .semibold)
    static let dsCaption = Font.system(size: 10.5)
    static let dsGauge = Font.system(size: 17, weight: .medium, design: .monospaced)
    static let dsMono = Font.system(size: 10, weight: .regular, design: .monospaced)
}

func stateColor(_ state: String) -> Color {
    switch state {
    case "GO": return .green
    case "TIGHT": return .yellow
    case "LOW": return .orange
    case "BLOCKED": return .red
    case "STALE": return .purple
    default: return .secondary
    }
}

// MARK: - Pieces

/// Quiet uppercase rule between groups, as in the system's own panels.
struct SectionHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            Text(title.uppercased())
                .font(.dsSection)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

/// The headline reading: a ring is read at a glance where a number needs focus.
struct Gauge: View {
    let remaining: Double
    let state: String
    let caption: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.01, min(1, remaining / 100)))
                .stroke(stateColor(state), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(remaining.rounded()))%")
                    .font(.dsGauge)
                Text(caption)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 76, height: 76)
    }
}

/// One window on one dense line: name, an inline track, the figure, the reset.
/// Instrument-panel compression rather than a card per reading -- the tile
/// layout spent ~90pt on what this says in 18.
struct WindowRow: View {
    let window: Window
    let strings: [String: String]

    private var tint: Color { stateColor(window.state) }
    private var alarming: Bool { ["LOW", "BLOCKED"].contains(window.state) }

    var body: some View {
        HStack(spacing: 7) {
            Text([window.pool, window.name].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11))
                .lineLimit(1)
                .layoutPriority(1)
            if window.binds {
                Text(strings["binds"] ?? "binds")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(tint.opacity(0.14), in: Capsule())
            }
            Spacer(minLength: 6)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.16))
                Capsule().fill(tint)
                    .frame(width: max(2, 56 * window.remaining / 100))
            }
            .frame(width: 56, height: 3)
            Text("\(Int(window.remaining.rounded()))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(alarming ? tint : Color.primary)
                .frame(width: 40, alignment: .trailing)
            Text(window.resetsIn)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 74, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.vertical, 1.5)
    }
}

struct SubscriptionBlock: View {
    let sub: Subscription
    let strings: [String: String]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(sub.sub).font(.dsTitle)
                if sub.isMain {
                    Text("MAIN")
                        .font(.system(size: 8.5, weight: .semibold)).kerning(0.5)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.accentColor, lineWidth: 1))
                }
                Spacer(minLength: 6)
                Text(sub.account)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            ForEach(Array(sub.windows.enumerated()), id: \.offset) { _, win in
                WindowRow(window: win, strings: strings)
            }
            if let reserve = sub.reserve, reserve.state != "GO" {
                Label(reserve.text, systemImage: "exclamationmark.triangle.fill")
                    .font(.dsCaption)
                    .foregroundStyle(stateColor(reserve.state))
                    .padding(.top, 2)
            }
            if !sub.note.isEmpty {
                Text(sub.note).font(.dsCaption).foregroundStyle(.tertiary)
            }
            if sub.selectable {
                Button(sub.isMain ? (strings["unsetMain"] ?? "Unset as main")
                                  : (strings["setAsMain"] ?? "Set as main")) {
                    onPick(sub.isMain ? "auto" : sub.key)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .padding(.top, 1)
            }
        }
    }
}

// MARK: - Panel

struct PanelView: View {
    let snapshot: Snapshot?
    let cliMissing: Bool
    let onPick: (String) -> Void
    let onMode: (String) -> Void
    let onDashboard: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    private var strings: [String: String] { snapshot?.strings ?? [:] }

    private var headline: Subscription? {
        guard let subs = snapshot?.subscriptions.filter({ !$0.windows.isEmpty }) else { return nil }
        return subs.first(where: \.isMain)
            ?? subs.min { ($0.binding?.remaining ?? 101) < ($1.binding?.remaining ?? 101) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            scrollingBody
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        Group {
            HStack {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .foregroundStyle(.secondary)
                Text("dipstick").font(.dsTitle)
                Spacer()
                if let snap = snapshot {
                    Text(String(snap.takenAt.suffix(8)))
                        .font(.dsMono)
                        .foregroundStyle(.tertiary)
                }
            }

            if cliMissing {
                Text(strings["notFound"] ?? "dipstick CLI not found in ~/.local/bin")
                    .font(.dsLabel).foregroundStyle(.secondary).padding(.vertical, 20)
            } else if snapshot == nil {
                Text(strings["noReading"] ?? "No reading yet")
                    .font(.dsLabel).foregroundStyle(.secondary).padding(.vertical, 20)
            }

            if let lead = headline, let win = lead.binding {
                HStack(spacing: 14) {
                    Gauge(remaining: win.remaining, state: win.state, caption: win.name)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lead.sub).font(.system(size: 13, weight: .semibold))
                        Text(win.why)
                            .font(.dsCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }

            if let snap = snapshot {
                HStack(spacing: 8) {
                    // The pin toggle lives here, not in a settings sheet: whether
                    // one subscription takes everything is the panel's main lever.
                    Toggle(isOn: Binding(
                        get: { snap.mainMode == "pinned" },
                        set: { onMode($0 ? "pinned" : "weighted") })) {
                        Text(strings["pinnedMode"] ?? "Pinned main")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    Spacer(minLength: 8)
                    if let next = snap.nextLaunch {
                        Text((strings["nextLaunch"] ?? "Next launch") + ":")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(next)
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    /// The list is the only part that can grow without bound -- four
    /// subscriptions with several windows each already overflows a screen -- so
    /// it scrolls while the gauge and the actions stay put.
    /// Fits the content when it is short and scrolls only when it is not — a
    /// greedy ScrollView otherwise pads the panel to its cap with empty space.
    private var scrollingBody: some View {
        ViewThatFits(in: .vertical) {
            listBody
            ScrollView(.vertical) { listBody }
        }
        .frame(maxHeight: 400)
        .scrollIndicators(.automatic)
    }

    private var listBody: some View {
            VStack(alignment: .leading, spacing: 0) {
            if let snap = snapshot {
                SectionHeader(title: strings["subscriptions"] ?? "subscriptions")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(snap.subscriptions.enumerated()), id: \.offset) { _, sub in
                        SubscriptionBlock(sub: sub, strings: strings, onPick: onPick)
                    }
                }

                let running = snap.runningCodex.reduce(0) { $0 + $1.count }
                if running > 0 {
                    SectionHeader(title: strings["runningSection"] ?? "running")
                    ForEach(Array(snap.runningCodex.prefix(4).enumerated()), id: \.offset) { _, proc in
                        HStack {
                            Text(proc.home.replacingOccurrences(
                                of: NSHomeDirectory(), with: "~"))
                                .font(.dsMono)
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text("\(proc.count)").font(.dsValue)
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
            }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().padding(.top, 10).padding(.bottom, 8)
            HStack(spacing: 14) {
                Button(strings["openDashboard"] ?? "Open dashboard…", action: onDashboard)
                Button(strings["refresh"] ?? "Refresh", action: onRefresh)
                Spacer()
                Button(strings["quit"] ?? "Quit", action: onQuit)
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
        }
    }
}

extension Subscription {
    /// The window a card's verdict comes from: the one the CLI marked as binding,
    /// falling back to the lowest reading.
    var binding: Window? {
        windows.first(where: \.binds) ?? windows.min { $0.remaining < $1.remaining }
    }
}

extension Window {
    var bindsLabel: String { "!" }
}
