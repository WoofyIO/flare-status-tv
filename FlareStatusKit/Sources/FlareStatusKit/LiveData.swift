import Foundation

/// The response of UptimeFlare's `/api/data` route.
///
/// ```json
/// { "up": 4, "down": 1, "updatedAt": 1700000000,
///   "monitors": { "<id>": { "up": true, "latency": 120, "location": "SEA", "message": "OK" } },
///   "maintenances": [ ... ] }   // maintenances: releases from 2026-01-01
/// ```
public struct LiveData: Equatable, Sendable {
    public var up: Int
    public var down: Int
    public var updatedAt: Int
    public var monitors: [String: LiveStatus]
    /// nil when the deployment predates the `maintenances` field.
    public var maintenances: [Maintenance]?

    public init(up: Int, down: Int, updatedAt: Int, monitors: [String: LiveStatus], maintenances: [Maintenance]?) {
        self.up = up
        self.down = down
        self.updatedAt = updatedAt
        self.monitors = monitors
        self.maintenances = maintenances
    }

    public static func parse(_ data: Data) throws -> LiveData {
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw DecodingFailure.notUptimeFlare("The /api/data response does not look like UptimeFlare.")
        }
        if raw.error != nil, raw.monitors == nil { throw DecodingFailure.noDataYet }
        guard let monitors = raw.monitors, let updatedAt = raw.updatedAt else {
            throw DecodingFailure.notUptimeFlare("The /api/data response has no monitors.")
        }
        return LiveData(
            up: raw.up ?? 0,
            down: raw.down ?? 0,
            updatedAt: updatedAt,
            monitors: monitors.mapValues {
                LiveStatus(up: $0.up, latency: $0.latency, location: $0.location, message: $0.message)
            },
            maintenances: raw.maintenances?.compactMap(\.maintenance)
        )
    }

    private struct Raw: Decodable {
        var up: Int?
        var down: Int?
        var updatedAt: Int?
        var monitors: [String: RawMonitor]?
        var maintenances: [RawMaintenance]?
        var error: String?

        enum CodingKeys: String, CodingKey { case up, down, updatedAt, monitors, maintenances, error }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            up = try c.decodeFlexibleInt(forKey: .up)
            down = try c.decodeFlexibleInt(forKey: .down)
            updatedAt = try c.decodeFlexibleInt(forKey: .updatedAt)
            monitors = try c.decodeIfPresent([String: RawMonitor].self, forKey: .monitors)
            maintenances = try? c.decodeIfPresent([RawMaintenance].self, forKey: .maintenances)
            error = try? c.decodeIfPresent(String.self, forKey: .error)
        }
    }

    private struct RawMonitor: Decodable {
        var up: Bool
        var latency: Int?
        var location: String?
        var message: String?

        enum CodingKeys: String, CodingKey { case up, latency, location, message }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            up = (try? c.decode(Bool.self, forKey: .up)) ?? false
            latency = try c.decodeFlexibleInt(forKey: .latency)
            location = try? c.decodeIfPresent(String.self, forKey: .location)
            message = try? c.decodeIfPresent(String.self, forKey: .message)
        }
    }

    private struct RawMaintenance: Decodable {
        var monitors: [String]?
        var title: String?
        var body: String?
        var start: FlexibleDate?
        var end: FlexibleDate?

        var maintenance: Maintenance? {
            guard let start = start?.date else { return nil }
            return Maintenance(
                title: title, body: body ?? "", start: start, end: end?.date, monitorIDs: monitors ?? [])
        }
    }
}

/// A maintenance time: UptimeFlare accepts a number or an ISO 8601 string and
/// passes it to JavaScript's `new Date(...)`.
struct FlexibleDate: Decodable {
    var date: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let number = try? c.decode(Double.self) {
            // JavaScript reads numbers as milliseconds. Values too small to be
            // a millisecond timestamp of this century are taken as seconds.
            date = Date(timeIntervalSince1970: number >= 100_000_000_000 ? number / 1000 : number)
        } else if let text = try? c.decode(String.self) {
            date = FlexibleDate.parse(text)
        }
    }

    static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
            [.withFullDate],
        ] {
            iso.formatOptions = options
            if let date = iso.date(from: trimmed) { return date }
        }
        // "2026-01-01T10:00" or "2026-01-01 10:00:00" without a zone: local time.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}

extension StatusSnapshot {
    /// The result of folding a `/api/data` response into a snapshot.
    public struct LiveMerge: Equatable, Sendable {
        public var snapshot: StatusSnapshot
        /// True when the live data disagrees with the stored history (a
        /// monitor changed state, or the monitor list changed), so the full
        /// page should be fetched again.
        public var needsFullRefresh: Bool
    }

    public func applying(_ live: LiveData) -> LiveMerge {
        var copy = self
        var needsFull = false
        let known = Set(monitors.map(\.id))
        if known != Set(live.monitors.keys) { needsFull = true }

        if live.updatedAt >= lastUpdate {
            copy.lastUpdate = live.updatedAt
            for index in copy.monitors.indices {
                guard let status = live.monitors[copy.monitors[index].id] else { continue }
                let before = copy.monitors[index].isUp
                copy.monitors[index].live = status
                if before != nil, before != status.up { needsFull = true }
            }
        }
        if let maintenances = live.maintenances { copy.maintenances = maintenances }
        return LiveMerge(snapshot: copy, needsFullRefresh: needsFull)
    }
}
