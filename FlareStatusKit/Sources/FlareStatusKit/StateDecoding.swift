import Foundation

public enum DecodingFailure: Error, Equatable, Sendable {
    /// The page is not an UptimeFlare status page (no Next.js data, or the
    /// data does not have UptimeFlare's shape).
    case notUptimeFlare(String)
    /// The page is UptimeFlare but its worker has not stored any state yet.
    case noDataYet
    /// The stored state is damaged or in a format this app does not know.
    case malformedState(String)
}

/// The monitor list UptimeFlare's page passes to the browser.
struct MonitorInfo: Decodable, Equatable {
    var id: String
    var name: String
    var tooltip: String?
    var statusPageLink: String?
    var hideLatencyChart: Bool?

    enum CodingKeys: String, CodingKey { case id, name, tooltip, statusPageLink, hideLatencyChart }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        tooltip = try? c.decodeIfPresent(String.self, forKey: .tooltip)
        statusPageLink = try? c.decodeIfPresent(String.self, forKey: .statusPageLink)
        hideLatencyChart = try? c.decodeIfPresent(Bool.self, forKey: .hideLatencyChart)
    }
}

/// The stored monitor state in either of UptimeFlare's two formats.
struct RawState: Decodable {
    var lastUpdate: Int
    var overallUp: Int
    var overallDown: Int
    var incident: [String: RawIncidents]
    var latency: [String: RawLatency]

    var format: StorageFormat {
        let compactedIncident = incident.values.contains { $0.wasColumnar }
        let compactedLatency = latency.values.contains { $0.wasCompacted }
        return (compactedIncident || compactedLatency) ? .compacted : .legacy
    }

    enum CodingKeys: String, CodingKey { case lastUpdate, overallUp, overallDown, incident, latency }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastUpdate = try c.decodeFlexibleInt(forKey: .lastUpdate) ?? 0
        overallUp = try c.decodeFlexibleInt(forKey: .overallUp) ?? 0
        overallDown = try c.decodeFlexibleInt(forKey: .overallDown) ?? 0
        incident = try c.decodeIfPresent([String: RawIncidents].self, forKey: .incident) ?? [:]
        latency = try c.decodeIfPresent([String: RawLatency].self, forKey: .latency) ?? [:]
    }
}

struct RawIncidents: Decodable {
    var incidents: [Incident]
    var wasColumnar: Bool

    private struct Record: Decodable {
        var start: [Int]
        var end: Int?
        var error: [String]
    }

    private struct Columnar: Decodable {
        var start: [[Int]]
        var end: [Int?]
        var error: [[String]]
    }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let records = try? single.decode([Record].self) {
            // Legacy KV format: an array of records; an open incident simply
            // has no `end` key.
            incidents = records.map { Incident(starts: $0.start, end: $0.end, errors: $0.error) }
            wasColumnar = false
            return
        }
        let columns = try single.decode(Columnar.self)
        guard columns.start.count == columns.end.count, columns.start.count == columns.error.count else {
            throw DecodingError.dataCorruptedError(
                in: single, debugDescription: "Incident columns have different lengths")
        }
        incidents = (0..<columns.start.count).map {
            Incident(starts: columns.start[$0], end: columns.end[$0], errors: columns.error[$0])
        }
        wasColumnar = true
    }
}

struct RawLatency: Decodable {
    var points: [LatencyPoint]
    var wasCompacted: Bool

    private struct Record: Decodable {
        var loc: String
        var ping: Int
        var time: Int

        enum CodingKeys: String, CodingKey { case loc, ping, time }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            loc = (try? c.decode(String.self, forKey: .loc)) ?? ""
            ping = try c.decodeFlexibleInt(forKey: .ping) ?? 0
            time = try c.decodeFlexibleInt(forKey: .time) ?? 0
        }

        var point: LatencyPoint { LatencyPoint(time: time, ping: ping, location: loc) }
    }

    private struct RunLength: Decodable {
        var v: [String]
        var c: [Int]
    }

    private enum Keys: String, CodingKey { case loc, ping, time, recent }

    init(from decoder: Decoder) throws {
        // An uncompacted array of records.
        if let single = try? decoder.singleValueContainer(), let records = try? single.decode([Record].self) {
            points = records.map(\.point)
            wasCompacted = false
            return
        }
        let c = try decoder.container(keyedBy: Keys.self)
        if c.contains(.recent) {
            // Legacy KV format: { recent: [...], all: [...] }. "recent" is the
            // 12-hour window the status page charts.
            points = try c.decode([Record].self, forKey: .recent).map(\.point)
            wasCompacted = false
            return
        }
        // D1 format: run-length-encoded locations plus hex-encoded
        // little-endian Uint16 (ping) and Uint32 (time) arrays.
        let runs = try c.decode(RunLength.self, forKey: .loc)
        let pingHex = try c.decode(String.self, forKey: .ping)
        let timeHex = try c.decode(String.self, forKey: .time)
        guard runs.v.count == runs.c.count,
              let pings = Hex.littleEndianIntegers(pingHex, width: 2),
              let times = Hex.littleEndianIntegers(timeHex, width: 4)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .ping, in: c, debugDescription: "Latency arrays are not valid hex")
        }
        var locations: [String] = []
        locations.reserveCapacity(pings.count)
        for (value, count) in zip(runs.v, runs.c) where count > 0 {
            locations.append(contentsOf: repeatElement(value, count: count))
        }
        guard pings.count == times.count, pings.count == locations.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .ping, in: c, debugDescription: "Latency columns have different lengths")
        }
        points = (0..<pings.count).map {
            LatencyPoint(time: times[$0], ping: pings[$0], location: locations[$0])
        }
        wasCompacted = true
    }
}

enum Hex {
    /// Decodes a hex string holding little-endian unsigned integers of
    /// `width` bytes each. Returns nil when the string is not valid.
    static func littleEndianIntegers(_ hex: String, width: Int) -> [Int]? {
        let bytes = Array(hex.utf8)
        let stride = width * 2
        guard bytes.count % stride == 0 else { return nil }
        var result: [Int] = []
        result.reserveCapacity(bytes.count / stride)
        var index = 0
        while index < bytes.count {
            var value = 0
            for byteIndex in 0..<width {
                guard let high = nibble(bytes[index + byteIndex * 2]),
                      let low = nibble(bytes[index + byteIndex * 2 + 1])
                else { return nil }
                value |= ((high << 4) | low) << (8 * byteIndex)
            }
            result.append(value)
            index += stride
        }
        return result
    }

    private static func nibble(_ c: UInt8) -> Int? {
        switch c {
        case 48...57: return Int(c) - 48
        case 97...102: return Int(c) - 87
        case 65...70: return Int(c) - 55
        default: return nil
        }
    }
}

extension KeyedDecodingContainer {
    /// JSON numbers written by JavaScript may be integers or floats.
    func decodeFlexibleInt(forKey key: Key) throws -> Int? {
        guard contains(key), (try? decodeNil(forKey: key)) == false else { return nil }
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key), value.isFinite { return Int(value) }
        return nil
    }
}

/// What UptimeFlare's page hands to the browser: the monitor list and the
/// stored state.
public struct PagePayload: Sendable {
    public var buildID: String?
    public var snapshot: StatusSnapshot
}

public enum PageParser {
    /// Extracts the snapshot from the HTML of an UptimeFlare status page.
    ///
    /// UptimeFlare renders nothing on the server; the page carries its data in
    /// the Next.js `__NEXT_DATA__` script as `props.pageProps`:
    /// `monitors` (id, name, tooltip, statusPageLink, hideLatencyChart) and
    /// either `compactedStateStr` (D1 releases, January 2026 and later) or
    /// `state` (older KV releases), both JSON strings.
    public static func parse(html: String) throws -> PagePayload {
        guard let json = nextDataJSON(in: html) else {
            throw DecodingFailure.notUptimeFlare("The page has no Next.js data block.")
        }
        return try parse(nextData: Data(json.utf8))
    }

    public static func parse(nextData: Data) throws -> PagePayload {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: nextData)
        } catch {
            throw DecodingFailure.notUptimeFlare("The page data does not look like UptimeFlare.")
        }
        guard let props = envelope.props?.pageProps, let infos = props.monitors else {
            throw DecodingFailure.notUptimeFlare("The page data has no monitor list.")
        }
        guard let stateData = props.stateData else {
            throw DecodingFailure.noDataYet
        }
        let raw: RawState
        do {
            raw = try JSONDecoder().decode(RawState.self, from: stateData)
        } catch {
            throw DecodingFailure.malformedState(describe(error))
        }
        guard raw.lastUpdate > 0 else { throw DecodingFailure.noDataYet }

        let monitors = infos.map { info in
            Monitor(
                id: info.id,
                name: info.name,
                tooltip: info.tooltip,
                statusPageLink: info.statusPageLink,
                hideLatencyChart: info.hideLatencyChart ?? false,
                incidents: raw.incident[info.id]?.incidents ?? [],
                latency: raw.latency[info.id]?.points ?? []
            )
        }
        let snapshot = StatusSnapshot(
            lastUpdate: raw.lastUpdate,
            monitors: monitors,
            format: raw.format,
            buildID: envelope.buildId
        )
        return PagePayload(buildID: envelope.buildId, snapshot: snapshot)
    }

    /// The script files the page loads, in document order.
    public static func scriptSources(in html: String) -> [String] {
        var result: [String] = []
        var rest = html[...]
        while let tag = rest.range(of: "<script") {
            guard let close = rest.range(of: ">", range: tag.upperBound..<rest.endIndex) else { break }
            let attributes = rest[tag.upperBound..<close.lowerBound]
            if let src = attributes.range(of: "src=\"") {
                let tail = attributes[src.upperBound...]
                if let quote = tail.firstIndex(of: "\"") {
                    result.append(String(tail[..<quote]))
                }
            }
            rest = rest[close.upperBound...]
        }
        return result
    }

    static func nextDataJSON(in html: String) -> Substring? {
        guard let marker = html.range(of: "id=\"__NEXT_DATA__\""),
              let open = html.range(of: ">", range: marker.upperBound..<html.endIndex),
              let close = html.range(of: "</script>", range: open.upperBound..<html.endIndex)
        else { return nil }
        return html[open.upperBound..<close.lowerBound]
    }

    private static func describe(_ error: Error) -> String {
        if case let DecodingError.dataCorrupted(context) = error { return context.debugDescription }
        if case let DecodingError.typeMismatch(_, context) = error { return context.debugDescription }
        if case let DecodingError.keyNotFound(key, _) = error { return "Missing \(key.stringValue)" }
        return "The stored state could not be read."
    }

    private struct Envelope: Decodable {
        var buildId: String?
        var props: Props?

        struct Props: Decodable {
            var pageProps: PageProps?
        }
    }

    private struct PageProps: Decodable {
        var monitors: [MonitorInfo]?
        var stateData: Data?

        enum CodingKeys: String, CodingKey { case monitors, compactedStateStr, state }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            monitors = try c.decodeIfPresent([MonitorInfo].self, forKey: .monitors)
            for key in [CodingKeys.compactedStateStr, .state] {
                if let text = try? c.decodeIfPresent(String.self, forKey: key), !text.isEmpty {
                    stateData = Data(text.utf8)
                    return
                }
            }
        }
    }
}
