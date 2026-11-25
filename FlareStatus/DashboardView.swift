import FlareStatusKit
import SwiftUI

/// The wall display: an overall banner, then every monitor, grouped the way
/// the status page groups them, with anything that is down first.
struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    let snapshot: StatusSnapshot
    /// Set while sample data is shown: leaves it and returns to setup.
    var leaveSample: (() -> Void)? = nil
    var openDetail: (Monitor) -> Void
    var openSettings: () -> Void

    @FocusState private var focusedID: String?
    @State private var lastInteraction = Date()
    @State private var lastTourStep = Date.distantPast
    /// The tile the idle tour last asked for, to tell its moves from those of a person.
    @State private var tourFocus: String?
    @State private var isOnScreen = false

    /// Seconds without remote input before the idle tour starts.
    static var idleSeconds: TimeInterval { DashboardView.launchValue("idleSeconds", default: 90) }
    /// Seconds the idle tour rests on each stop.
    static var tourSeconds: TimeInterval { DashboardView.launchValue("tourSeconds", default: 8) }

    /// `-idleSeconds 3 -tourSeconds 1` on the command line shortens the waits, for tests.
    private static func launchValue(_ key: String, default value: TimeInterval) -> TimeInterval {
        let override = UserDefaults.standard.double(forKey: key)
        return override > 0 ? override : value
    }

    var body: some View {
        let now = Date()
        let layout = Layout(monitorCount: snapshot.monitors.count)
        let sections = snapshot.sections
        let down = snapshot.downMonitors
        let downTiles = down.map { "down-\($0.id)" }
        let sectionTiles = sections.map { $0.monitors.map(\.id) }
        // Where the idle tour moves the focus, and the order tiles appear in.
        let tour = Tour(
            stops: IdleTour.stops(leading: downTiles, sections: sectionTiles, columns: layout.columns),
            order: downTiles + sectionTiles.flatMap { $0 })

        VStack(spacing: 0) {
            BannerView(
                snapshot: snapshot, state: model.state, pageHost: model.selectedPage?.host,
                leaveSample: leaveSample, openSettings: openSettings)
                .padding(.horizontal, 80)
                .padding(.top, 50)
                .padding(.bottom, 26)
                // Pressing up from any tile lands on the gear.
                .focusSection()

            ScrollView {
                // Not lazy on purpose: the idle tour focuses tiles that are far
                // off screen, and a tile that has not been built cannot take focus.
                VStack(alignment: .leading, spacing: 44) {
                    ForEach(snapshot.activeMaintenances(at: now)) { maintenance in
                        MaintenanceNotice(maintenance: maintenance, snapshot: snapshot, upcoming: false)
                    }
                    if !down.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHeader(title: "Down now", trailing: "\(down.count) of \(snapshot.monitors.count)", color: Theme.down, identifier: "down-now")
                            TileRows(items: down, columns: down.count == 1 ? 1 : 2, spacing: 28) { monitor in
                                Button { openDetail(monitor) } label: {
                                    DownCard(monitor: monitor, now: now)
                                }
                                .buttonStyle(TileButtonStyle(fill: Theme.downFill, cornerRadius: 24, focusScale: down.count == 1 ? 1.015 : 1.03))
                                .focused($focusedID, equals: "down-\(monitor.id)")
                                .accessibilityIdentifier("down-\(monitor.id)")
                            }
                        }
                    }
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 20) {
                            if let name = section.name {
                                SectionHeader(
                                    title: name,
                                    trailing: "\(section.upCount)/\(section.monitors.count) operational",
                                    color: section.downCount == 0 ? Theme.up : (section.upCount == 0 ? Theme.down : Theme.warning),
                                    identifier: "group-\(name)")
                            }
                            TileRows(items: section.monitors, columns: layout.columns, spacing: layout.spacing) { monitor in
                                Button { openDetail(monitor) } label: {
                                    MonitorCard(
                                        monitor: monitor,
                                        name: Format.shortName(monitor.name, inGroup: section.name),
                                        status: snapshot.status(of: monitor, at: now),
                                        layout: layout, now: now)
                                }
                                .buttonStyle(TileButtonStyle(focusScale: layout.columns == 1 ? 1.015 : (layout.columns == 2 ? 1.03 : 1.045)))
                                .focused($focusedID, equals: monitor.id)
                                .accessibilityIdentifier("monitor-\(monitor.id)")
                            }
                        }
                    }
                    ForEach(snapshot.upcomingMaintenances(at: now)) { maintenance in
                        MaintenanceNotice(maintenance: maintenance, snapshot: snapshot, upcoming: true)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.top, 24)
                .padding(.bottom, 80)
                .focusSection()
            }
        }
        .ignoresSafeArea()
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            isOnScreen = true
            lastInteraction = Date()
        }
        .onDisappear { isOnScreen = false }
        .onChange(of: focusedID) {
            // Focus moved by the tour is not a person using the remote.
            guard focusedID != tourFocus else { return }
            lastInteraction = Date()
            tourFocus = nil
        }
        .task(id: tour) {
            // When nobody has touched the remote for a while, move the focus
            // down the page a few rows at a time, then start again at the top,
            // so a page of several screens is seen in full. Moving the focus
            // is how tvOS scrolls.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let now = Date()
                guard isOnScreen, model.autoScroll, tour.stops.count > 1,
                      now.timeIntervalSince(lastInteraction) >= DashboardView.idleSeconds,
                      now.timeIntervalSince(lastTourStep) >= DashboardView.tourSeconds,
                      let next = IdleTour.next(after: focusedID, stops: tour.stops, order: tour.order)
                else { continue }
                lastTourStep = now
                tourFocus = next
                focusedID = next
            }
        }
    }

    private struct Tour: Equatable {
        let stops: [String]
        let order: [String]
    }

    /// How dense the grid is, from one huge tile to a wall of sixty.
    struct Layout {
        let columns: Int
        let spacing: CGFloat
        let historyDays: Int
        let nameSize: CGFloat
        let detailSize: CGFloat
        let stripHeight: CGFloat
        let padding: CGFloat

        init(monitorCount: Int) {
            switch monitorCount {
            case ...1: (columns, historyDays, nameSize, detailSize, stripHeight, padding) = (1, 90, 46, 32, 56, 38)
            case ...4: (columns, historyDays, nameSize, detailSize, stripHeight, padding) = (2, 90, 40, 30, 44, 34)
            case ...9: (columns, historyDays, nameSize, detailSize, stripHeight, padding) = (3, 60, 34, 26, 34, 28)
            case ...28: (columns, historyDays, nameSize, detailSize, stripHeight, padding) = (4, 45, 30, 24, 28, 24)
            default: (columns, historyDays, nameSize, detailSize, stripHeight, padding) = (5, 30, 27, 22, 22, 20)
            }
            spacing = columns >= 4 ? 22 : 28
        }

    }
}

private struct SectionHeader: View {
    let title: String
    let trailing: String
    let color: Color
    let identifier: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 38, weight: .bold))
                .accessibilityIdentifier(identifier)
            Spacer()
            Text(trailing)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

/// A grid built from plain rows. Every tile exists from the start, which a
/// lazy grid does not guarantee.
private struct TileRows<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    @ViewBuilder let tile: (Item) -> Tile

    var body: some View {
        let columns = max(1, columns)
        let rowStarts = Array(stride(from: 0, to: items.count, by: columns))
        VStack(spacing: spacing) {
            ForEach(rowStarts, id: \.self) { start in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        if start + column < items.count {
                            tile(items[start + column])
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
    }
}

/// The headline: one glance tells whether anything needs attention.
struct BannerView: View {
    let snapshot: StatusSnapshot
    let state: PageState
    let pageHost: String?
    var leaveSample: (() -> Void)? = nil
    var openSettings: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            let down = snapshot.downCount
            let total = snapshot.monitors.count
            let stale = snapshot.isStale(now: now)
            let tint: Color = down > 0 ? Theme.down : (stale || state.error != nil ? Theme.warning : Theme.up)

            HStack(spacing: 30) {
                Image(systemName: down > 0 ? "exclamationmark.octagon.fill" : (stale || state.error != nil ? "clock.badge.exclamationmark.fill" : "checkmark.circle.fill"))
                    .font(.system(size: 92, weight: .bold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 6) {
                    Text(headline(down: down, total: total))
                        .font(.system(size: 60, weight: .heavy))
                        .foregroundStyle(down > 0 ? Theme.down : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(subline(now: now, stale: stale))
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(stale || state.error != nil ? Theme.warning : Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 20)
                if let leaveSample {
                    // Sample data must never be mistaken for a real status page.
                    Button(action: leaveSample) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Sample data", systemImage: "theatermasks.fill")
                                .font(.system(size: 28, weight: .heavy))
                                .foregroundStyle(Theme.warning)
                            Text("Select to set up your own page")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 26)
                        .frame(height: 84)
                    }
                    .buttonStyle(TileButtonStyle(fill: Theme.warning.opacity(0.16), cornerRadius: 42, focusScale: 1.03))
                    .accessibilityIdentifier("sample-data-badge")
                    .accessibilityLabel("Sample data. Select to set up your own page.")
                }
                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 84, height: 84)
                }
                .buttonStyle(TileButtonStyle(cornerRadius: 42))
                .accessibilityLabel("Settings")
            }
        }
    }

    private func headline(down: Int, total: Int) -> String {
        if total == 0 { return "No monitors configured" }
        if down == 0 { return total == 1 ? "Operational" : "All \(total) systems operational" }
        if down == total { return total == 1 ? "Down" : "All \(total) systems down" }
        return "\(down) of \(total) systems down"
    }

    private func subline(now: Date, stale: Bool) -> String {
        let name = (snapshot.title ?? pageHost ?? "Status") + (leaveSample == nil ? "" : " (sample data)")
        let checked = "checked \(Format.ago(snapshot.lastUpdateDate, now: now))"
        if let error = state.error {
            return "\(name)  ·  \(error.title)  ·  last data \(Format.ago(snapshot.lastUpdateDate, now: now))"
        }
        if stale {
            return "\(name)  ·  Data is stale: the status page last \(checked)"
        }
        return "\(name)  ·  \(checked)"
    }
}

/// A monitor that is down right now: large, red, and says why.
private struct DownCard: View {
    let monitor: Monitor
    let now: Date

    private var spokenLabel: String {
        var parts = [monitor.name, "down"]
        if let error = monitor.currentError { parts.append(error) }
        if let since = monitor.downSince {
            parts.append("for \(Format.duration(Int(now.timeIntervalSince1970) - since))")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 8) {
                Text(monitor.name)
                    .font(.system(size: 40, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(monitor.currentError ?? "No response")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                if let since = monitor.downSince {
                    Text("Down for \(Format.duration(Int(now.timeIntervalSince1970) - since))  ·  since \(Format.since(since, now: now))")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(30)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }
}

private struct MonitorCard: View {
    let monitor: Monitor
    let name: String
    let status: MonitorStatus
    let layout: DashboardView.Layout
    let now: Date

    var body: some View {
        let seconds = Int(now.timeIntervalSince1970)
        let uptime = monitor.uptimePercent(now: seconds)
        VStack(alignment: .leading, spacing: layout.padding * 0.5) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Theme.color(for: status))
                    .frame(width: layout.nameSize * 0.55, height: layout.nameSize * 0.55)
                Text(name)
                    .font(.system(size: layout.nameSize, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(detail)
                    .font(.system(size: layout.detailSize, weight: .medium))
                    .foregroundStyle(status == .down ? Theme.down : (status == .maintenance ? Theme.warning : Theme.secondaryText))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(Format.percent(uptime))
                    .font(.system(size: layout.detailSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.color(forUptime: uptime))
            }
            HistoryStrip(days: monitor.dailyUptime(days: layout.historyDays, now: seconds))
                .frame(height: layout.stripHeight)
        }
        .foregroundStyle(.white)
        .padding(layout.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(uptime: uptime))
    }

    private func spokenLabel(uptime: Double?) -> String {
        let state: String
        switch status {
        case .up: state = "operational"
        case .down: state = "down"
        case .maintenance: state = "under maintenance"
        case .unknown: state = "no data yet"
        }
        var parts = [name, state]
        if status == .up, let latency = Format.latency(for: monitor) { parts.append(latency) }
        if uptime != nil { parts.append("uptime \(Format.percent(uptime))") }
        return parts.joined(separator: ", ")
    }

    private var detail: String {
        switch status {
        case .down: return "Down"
        case .maintenance: return "Maintenance"
        case .unknown: return "No data yet"
        case .up:
            let parts = [Format.latency(for: monitor), monitor.isHeartbeat ? nil : Format.location(monitor.currentLocation)]
            let text = parts.compactMap { $0 }.joined(separator: "  ·  ")
            return text.isEmpty ? "Operational" : text
        }
    }
}

struct MaintenanceNotice: View {
    let maintenance: Maintenance
    let snapshot: StatusSnapshot
    let upcoming: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 40))
                .foregroundStyle(upcoming ? Theme.secondaryText : Theme.warning)
            VStack(alignment: .leading, spacing: 6) {
                Text((upcoming ? "Upcoming: " : "") + (maintenance.title ?? "Scheduled maintenance"))
                    .font(.system(size: 32, weight: .bold))
                if !maintenance.body.isEmpty {
                    Text(maintenance.body)
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(3)
                }
                Text(schedule)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((upcoming ? Theme.card : Theme.warning.opacity(0.16)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder((upcoming ? Color.white.opacity(0.08) : Theme.warning.opacity(0.6)), lineWidth: 2))
    }

    private var schedule: String {
        var text = maintenance.start.formatted(date: .abbreviated, time: .shortened)
        if let end = maintenance.end {
            text += " to " + end.formatted(date: .abbreviated, time: .shortened)
        } else {
            text += ", until further notice"
        }
        let names = maintenance.monitorIDs.compactMap { snapshot.monitor(id: $0)?.name }
        if !names.isEmpty { text += "  ·  " + names.joined(separator: ", ") }
        return text
    }
}

#Preview("Outage") {
    DashboardView(snapshot: SampleData.snapshot(.outage), openDetail: { _ in }, openSettings: {})
        .environmentObject(AppModel(demo: .outage))
}

#Preview("60+ monitors") {
    DashboardView(snapshot: SampleData.snapshot(.large), openDetail: { _ in }, openSettings: {})
        .environmentObject(AppModel(demo: .large))
}

#Preview("Single monitor") {
    DashboardView(snapshot: SampleData.snapshot(.single), openDetail: { _ in }, openSettings: {})
        .environmentObject(AppModel(demo: .single))
}
