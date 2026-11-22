import Charts
import FlareStatusKit
import SwiftUI

/// Everything known about one monitor: response times, the 90-day history and
/// its recent outages.
struct MonitorDetailView: View {
    let monitor: Monitor
    let snapshot: StatusSnapshot

    var body: some View {
        let now = Date()
        let seconds = Int(now.timeIntervalSince1970)
        let status = snapshot.status(of: monitor, at: now)
        let outages = Array(monitor.outages.prefix(25))

        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header(status: status, seconds: seconds)
                stats(seconds: seconds)
                if !monitor.hideLatencyChart, monitor.latency.count > 1 {
                    LatencyChart(monitor: monitor)
                }
                history(seconds: seconds)
                VStack(alignment: .leading, spacing: 16) {
                    Text(outages.isEmpty ? "No outages in the last 90 days" : "Recent outages")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(outages.isEmpty ? Theme.secondaryText : .white)
                    ForEach(Array(outages.enumerated()), id: \.offset) { _, outage in
                        // Buttons so the remote can move through a long list.
                        Button {} label: { OutageRow(outage: outage, now: seconds) }
                            .buttonStyle(TileButtonStyle(fill: outage.isOpen ? Theme.downFill : Theme.card, cornerRadius: 18, focusScale: 1.015))
                    }
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 60)
        }
        .background(Theme.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .horizontal)
    }

    private func header(status: MonitorStatus, seconds: Int) -> some View {
        HStack(alignment: .top, spacing: 26) {
            Circle()
                .fill(Theme.color(for: status))
                .frame(width: 44, height: 44)
                .padding(.top, 16)
            VStack(alignment: .leading, spacing: 6) {
                Text(monitor.name)
                    .font(.system(size: 62, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(statusLine(status: status, seconds: seconds))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.color(for: status))
                    .lineLimit(2)
                if let tooltip = monitor.tooltip, !tooltip.isEmpty {
                    Text(tooltip)
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func statusLine(status: MonitorStatus, seconds: Int) -> String {
        switch status {
        case .up: return "Operational"
        case .maintenance: return "Under maintenance"
        case .unknown: return "No data yet"
        case .down:
            var text = "Down"
            if let since = monitor.downSince { text += " for \(Format.duration(seconds - since))" }
            if let error = monitor.currentError { text += "  ·  \(error)" }
            return text
        }
    }

    private func stats(seconds: Int) -> some View {
        let uptime = monitor.uptimePercent(now: seconds)
        let lastCheck = monitor.lastLatency?.time
        return HStack(spacing: 24) {
            StatTile(
                label: "Uptime, last \(monitoredDays(seconds)) days",
                value: Format.percent(uptime), color: Theme.color(forUptime: uptime))
            StatTile(
                label: monitor.isHeartbeat ? "Last heartbeat" : "Response time",
                value: monitor.isHeartbeat
                    ? monitor.currentPing.map { "\(Format.duration($0)) ago" } ?? "–"
                    : monitor.currentPing.map { "\($0) ms" } ?? "–")
            StatTile(label: "Checked from", value: Format.location(monitor.currentLocation) ?? "–")
            StatTile(
                label: "Last measurement",
                value: lastCheck.map { Format.ago(Date(timeIntervalSince1970: TimeInterval($0)), now: Date()) } ?? "–")
        }
    }

    private func monitoredDays(_ seconds: Int) -> Int {
        guard let start = monitor.monitoringStart else { return 90 }
        return min(90, max(1, (seconds - start + 86_399) / 86_400))
    }

    private func history(seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily uptime")
                .font(.system(size: 34, weight: .bold))
            HistoryStrip(days: monitor.dailyUptime(days: 90, now: seconds), gapRatio: 0.25)
                .frame(height: 64)
            HStack {
                Text("90 days ago")
                Spacer()
                Text("Today")
            }
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    var color: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 46, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct LatencyChart: View {
    let monitor: Monitor

    var body: some View {
        let points = monitor.latency
        let hours = max(1, Int((Double((points.last?.time ?? 0) - (points.first?.time ?? 0)) / 3600).rounded()))
        VStack(alignment: .leading, spacing: 12) {
            Text(monitor.isHeartbeat ? "Heartbeat age, last \(hours) h" : "Response time, last \(hours) h")
                .font(.system(size: 34, weight: .bold))
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Time", Date(timeIntervalSince1970: TimeInterval(point.time))),
                        y: .value("Value", point.ping))
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.up.opacity(0.35), Theme.up.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(
                        x: .value("Time", Date(timeIntervalSince1970: TimeInterval(point.time))),
                        y: .value("Value", point.ping))
                        .foregroundStyle(Theme.up)
                        .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: hours > 6 ? 2 : 1)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel(format: .dateTime.hour(), anchor: .top)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel {
                        if let number = value.as(Int.self) {
                            Text(monitor.isHeartbeat ? "\(number) s" : "\(number) ms")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
            .frame(height: 300)
            .padding(24)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct OutageRow: View {
    let outage: Incident
    let now: Int

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Format.dateTime(outage.start))
                    .font(.system(size: 28, weight: .bold))
                Text(outage.isOpen ? "ongoing, \(Format.duration(outage.duration(now: now)))" : "lasted \(Format.duration(outage.duration(now: now)))")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(outage.isOpen ? .white : Theme.secondaryText)
            }
            .frame(width: 420, alignment: .leading)
            Text(outage.distinctErrors.joined(separator: "\n"))
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Down monitor") {
    let snapshot = SampleData.snapshot(.outage)
    return MonitorDetailView(monitor: snapshot.downMonitors[0], snapshot: snapshot)
}
