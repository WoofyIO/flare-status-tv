import Foundation

/// One latency sample recorded by the UptimeFlare worker.
public struct LatencyPoint: Equatable, Sendable {
    /// Unix seconds.
    public var time: Int
    /// Milliseconds for normal monitors. Heartbeat ("push") monitors on some
    /// forks store the heartbeat age in seconds here instead.
    public var ping: Int
    /// Where the check ran: a Cloudflare colo code such as "SEA", or a
    /// "country/city" pair for proxied checks.
    public var location: String

    public init(time: Int, ping: Int, location: String) {
        self.time = time
        self.ping = ping
        self.location = location
    }
}

/// One outage. UptimeFlare appends a new start time and error every time the
/// failure reason changes during the same outage.
public struct Incident: Equatable, Sendable {
    public var starts: [Int]
    /// Unix seconds, nil while the outage is still open.
    public var end: Int?
    public var errors: [String]

    public init(starts: [Int], end: Int?, errors: [String]) {
        self.starts = starts
        self.end = end
        self.errors = errors
    }

    public var start: Int { starts.first ?? 0 }
    public var isOpen: Bool { end == nil }

    /// UptimeFlare stores a zero-length "dummy" incident as the first entry to
    /// remember when monitoring began. It is not a real outage.
    public var isPlaceholder: Bool { errors.first == "dummy" }

    public func duration(now: Int) -> Int { max(0, (end ?? now) - start) }

    /// The distinct failure reasons, in the order they appeared.
    public var distinctErrors: [String] {
        var seen = Set<String>()
        return errors.filter { seen.insert($0).inserted }
    }
}

/// Current state reported by `/api/data`.
public struct LiveStatus: Equatable, Sendable {
    public var up: Bool
    public var latency: Int?
    public var location: String?
    public var message: String?

    public init(up: Bool, latency: Int?, location: String?, message: String?) {
        self.up = up
        self.latency = latency
        self.location = location
        self.message = message
    }
}

public enum MonitorStatus: Equatable, Sendable {
    case up, down, maintenance, unknown
}

/// The uptime of one calendar day, as drawn in the history strip.
public struct DayUptime: Equatable, Sendable, Identifiable {
    public var dayStart: Int
    /// 0...100, nil when the monitor did not exist yet on that day.
    public var percent: Double?
    public var downSeconds: Int

    public var id: Int { dayStart }
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(dayStart)) }
}

public struct Monitor: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var tooltip: String?
    public var statusPageLink: String?
    public var hideLatencyChart: Bool
    /// Oldest first, including the placeholder entry.
    public var incidents: [Incident]
    /// Oldest first; the recent window UptimeFlare keeps (about 12 hours).
    public var latency: [LatencyPoint]
    public var live: LiveStatus?

    public init(
        id: String,
        name: String,
        tooltip: String? = nil,
        statusPageLink: String? = nil,
        hideLatencyChart: Bool = false,
        incidents: [Incident] = [],
        latency: [LatencyPoint] = [],
        live: LiveStatus? = nil
    ) {
        self.id = id
        self.name = name
        self.tooltip = tooltip
        self.statusPageLink = statusPageLink
        self.hideLatencyChart = hideLatencyChart
        self.incidents = incidents
        self.latency = latency
        self.live = live
    }

        /// nil when the worker has not recorded anything for this monitor yet.
    public var isUp: Bool? {
        if let live { return live.up }
        if let last = incidents.last { return last.end != nil }
        return nil
    }

    public var isDown: Bool { isUp == false }

    public var openIncident: Incident? {
        guard let last = incidents.last, last.isOpen else { return nil }
        return last
    }

    public var currentError: String? {
        guard isDown else { return nil }
        return openIncident?.errors.last ?? live?.message
    }

    /// Unix seconds the current outage started, if the monitor is down.
    public var downSince: Int? { openIncident?.start }

    public var lastLatency: LatencyPoint? { latency.last }

    /// The most recent latency in milliseconds (or heartbeat age in seconds
    /// for heartbeat monitors).
    public var currentPing: Int? { live?.latency ?? lastLatency?.ping }
    public var currentLocation: String? { live?.location ?? lastLatency?.location }

    /// Forks that add heartbeat monitors record the location as "push" and
    /// the age of the last heartbeat (seconds) in place of a latency.
    public var isHeartbeat: Bool {
        currentLocation?.lowercased() == "push"
    }

    public var monitoringStart: Int? { incidents.first?.start }

    /// Real outages, newest first.
    public var outages: [Incident] {
        incidents.filter { !$0.isPlaceholder }.reversed()
    }

    /// Overall uptime since monitoring began (at most the 90 days UptimeFlare
    /// keeps), computed the same way as the web status page.
    public func uptimePercent(now: Int) -> Double? {
        guard let begin = monitoringStart else { return nil }
        let total = now - begin
        guard total > 0 else { return nil }
        let down = incidents.reduce(0) { $0 + $1.duration(now: now) }
        return min(100, max(0, Double(total - down) / Double(total) * 100))
    }

    /// Per-day uptime for the last `days` days, oldest first, ending today.
    public func dailyUptime(days: Int = 90, now: Int, calendar: Calendar = .current) -> [DayUptime] {
        guard days > 0 else { return [] }
        let today = Int(calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(now))).timeIntervalSince1970)
        let begin = monitoringStart
        return (0..<days).reversed().map { back in
            let dayStart = today - back * 86_400
            let dayEnd = dayStart + 86_400
            guard let begin else { return DayUptime(dayStart: dayStart, percent: nil, downSeconds: 0) }
            let monitored = Monitor.overlap(dayStart, dayEnd, begin, now)
            guard monitored > 0 else { return DayUptime(dayStart: dayStart, percent: nil, downSeconds: 0) }
            let down = incidents.reduce(0) { $0 + Monitor.overlap(dayStart, dayEnd, $1.start, $1.end ?? now) }
            let percent = Double(monitored - min(down, monitored)) / Double(monitored) * 100
            return DayUptime(dayStart: dayStart, percent: percent, downSeconds: down)
        }
    }

    static func overlap(_ a1: Int, _ a2: Int, _ b1: Int, _ b2: Int) -> Int {
        max(0, min(a2, b2) - max(a1, b1))
    }
}

public struct MonitorGroup: Equatable, Sendable, Identifiable {
    public var name: String
    public var monitorIDs: [String]

    public var id: String { name }

    public init(name: String, monitorIDs: [String]) {
        self.name = name
        self.monitorIDs = monitorIDs
    }
}

public struct Maintenance: Equatable, Sendable, Identifiable {
    public var title: String?
    public var body: String
    public var start: Date
    public var end: Date?
    public var monitorIDs: [String]

    public var id: String { "\(start.timeIntervalSince1970)-\(title ?? "")-\(body.prefix(24))" }

    public init(title: String?, body: String, start: Date, end: Date?, monitorIDs: [String]) {
        self.title = title
        self.body = body
        self.start = start
        self.end = end
        self.monitorIDs = monitorIDs
    }

    public func isActive(at date: Date) -> Bool {
        date >= start && (end.map { date <= $0 } ?? true)
    }

    public func isUpcoming(at date: Date) -> Bool { date < start }
}

/// Which stored-state format the deployment served.
public enum StorageFormat: String, Equatable, Sendable {
    /// Columnar, hex-encoded state used since the January 2026 D1 migration.
    case compacted
    /// The plain JSON state used by the older KV-backed releases.
    case legacy
}

/// Everything the app knows about one status page at one moment.
public struct StatusSnapshot: Equatable, Sendable {
    public var title: String?
    /// Unix seconds of the worker's last run.
    public var lastUpdate: Int
    public var monitors: [Monitor]
    /// As configured in UptimeFlare's `pageConfig.group`; empty when the page
    /// is not grouped or the groups could not be read.
    public var groups: [MonitorGroup]
    public var maintenances: [Maintenance]
    public var format: StorageFormat
    public var buildID: String?

    public init(
        title: String? = nil,
        lastUpdate: Int,
        monitors: [Monitor],
        groups: [MonitorGroup] = [],
        maintenances: [Maintenance] = [],
        format: StorageFormat = .compacted,
        buildID: String? = nil
    ) {
        self.title = title
        self.lastUpdate = lastUpdate
        self.monitors = monitors
        self.groups = groups
        self.maintenances = maintenances
        self.format = format
        self.buildID = buildID
    }

    public var lastUpdateDate: Date { Date(timeIntervalSince1970: TimeInterval(lastUpdate)) }

    public var downMonitors: [Monitor] { monitors.filter(\.isDown) }
    public var downCount: Int { downMonitors.count }
    public var upCount: Int { monitors.filter { $0.isUp == true }.count }

    /// UptimeFlare's worker runs every minute; the web page treats data older
    /// than five minutes as out of date.
    public static let staleAfterSeconds = 300

    public func isStale(now: Date) -> Bool {
        Int(now.timeIntervalSince1970) - lastUpdate > StatusSnapshot.staleAfterSeconds
    }

    public func activeMaintenances(at date: Date) -> [Maintenance] {
        maintenances.filter { $0.isActive(at: date) }
    }

    public func upcomingMaintenances(at date: Date) -> [Maintenance] {
        maintenances.filter { $0.isUpcoming(at: date) }.sorted { $0.start < $1.start }
    }

    public func status(of monitor: Monitor, at date: Date) -> MonitorStatus {
        if activeMaintenances(at: date).contains(where: { $0.monitorIDs.contains(monitor.id) }) {
            return .maintenance
        }
        switch monitor.isUp {
        case .some(true): return .up
        case .some(false): return .down
        case .none: return .unknown
        }
    }

    public func monitor(id: String) -> Monitor? { monitors.first { $0.id == id } }

    /// Monitors arranged for display. Follows the configured groups and their
    /// order; monitors that are in no group are collected at the end so a
    /// failing monitor can never be hidden.
    public var sections: [MonitorSection] {
        guard !groups.isEmpty else {
            return monitors.isEmpty ? [] : [MonitorSection(name: nil, monitors: monitors)]
        }
        let byID = Dictionary(monitors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var used = Set<String>()
        var result: [MonitorSection] = []
        for group in groups {
            let members = group.monitorIDs.compactMap { byID[$0] }
            guard !members.isEmpty else { continue }
            members.forEach { used.insert($0.id) }
            result.append(MonitorSection(name: group.name, monitors: members))
        }
        let rest = monitors.filter { !used.contains($0.id) }
        if !rest.isEmpty {
            result.append(MonitorSection(name: "Other", monitors: rest))
        }
        return result
    }
}

public struct MonitorSection: Equatable, Sendable, Identifiable {
    public var name: String?
    public var monitors: [Monitor]

    public var id: String { name ?? "__all__" }
    public var downCount: Int { monitors.filter(\.isDown).count }
    public var upCount: Int { monitors.count - downCount }
}
