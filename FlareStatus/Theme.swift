import FlareStatusKit
import SwiftUI

/// Colours and text helpers shared by every screen. Sizes are tuned for a
/// television seen from across a room.
enum Theme {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.063)
    static let card = Color(red: 0.094, green: 0.106, blue: 0.137)
    static let cardRaised = Color(red: 0.14, green: 0.155, blue: 0.2)
    static let up = Color(red: 0.184, green: 0.824, blue: 0.478)
    static let upSoft = Color(red: 0.42, green: 0.85, blue: 0.62).opacity(0.75)
    static let down = Color(red: 1.0, green: 0.302, blue: 0.31)
    static let downFill = Color(red: 0.55, green: 0.08, blue: 0.1)
    static let warning = Color(red: 0.96, green: 0.647, blue: 0.141)
    static let muted = Color.white.opacity(0.14)
    static let secondaryText = Color.white.opacity(0.62)

    static func color(for status: MonitorStatus) -> Color {
        switch status {
        case .up: return up
        case .down: return down
        case .maintenance: return warning
        case .unknown: return .gray
        }
    }

    /// The colour scale UptimeFlare's web page uses for uptime percentages.
    static func color(forUptime percent: Double?) -> Color {
        guard let percent else { return muted }
        if percent >= 99.9 { return up }
        if percent >= 99 { return upSoft }
        if percent >= 95 { return warning }
        return down
    }
}

enum Format {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        if value >= 100 { return "100%" }
        return String(format: value >= 99.995 ? "%.3f%%" : "%.2f%%", value)
    }

    /// "12 s", "4 min", "3 h 20 min", "2 d 5 h".
    static func duration(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 48 { return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min" }
        return "\(hours / 24) d \(hours % 24) h"
    }

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        return seconds < 5 ? "just now" : "\(duration(seconds)) ago"
    }

    static func latency(for monitor: Monitor) -> String? {
        guard let ping = monitor.currentPing else { return nil }
        if monitor.isHeartbeat { return "beat \(duration(ping)) ago" }
        return "\(ping) ms"
    }

    static func location(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return code.lowercased() == "push" ? "Heartbeat" : code
    }

    static func dateTime(_ seconds: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(seconds)).formatted(date: .abbreviated, time: .shortened)
    }

    /// A start time: just the clock time for today, the date as well for older ones.
    static func since(_ seconds: Int, now: Date) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        return Calendar.current.isDate(date, inSameDayAs: now) ? time(seconds) : dateTime(seconds)
    }

    /// Status pages often repeat the group in every monitor name ("Media - Player"
    /// inside the group "Media"). Inside that group the prefix is noise.
    static func shortName(_ name: String, inGroup group: String?) -> String {
        guard let group, !group.isEmpty, name.count > group.count,
              name.lowercased().hasPrefix(group.lowercased())
        else { return name }
        let rest = name.dropFirst(group.count)
        let trimmed = rest.drop { " -–—:|/".contains($0) }
        guard trimmed.count < rest.count, !trimmed.isEmpty else { return name }
        return String(trimmed)
    }

    static func time(_ seconds: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(seconds)).formatted(date: .omitted, time: .shortened)
    }
}

/// A focusable tile: lifts and gains a bright edge when the remote lands on it.
struct TileButtonStyle: ButtonStyle {
    var fill: Color = Theme.card
    var cornerRadius: CGFloat = 20
    /// How much the tile grows when focused; wide tiles need less.
    var focusScale: CGFloat = 1.045

    func makeBody(configuration: Configuration) -> some View {
        Tile(configuration: configuration, fill: fill, cornerRadius: cornerRadius, focusScale: focusScale)
    }

    private struct Tile: View {
        let configuration: ButtonStyleConfiguration
        let fill: Color
        let cornerRadius: CGFloat
        let focusScale: CGFloat
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(isFocused ? 0.95 : 0.06), lineWidth: isFocused ? 5 : 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? focusScale : 1))
                .shadow(color: .black.opacity(isFocused ? 0.6 : 0), radius: 24, y: 14)
                .animation(.easeOut(duration: 0.16), value: isFocused)
        }
    }
}
