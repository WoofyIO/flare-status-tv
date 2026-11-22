import Foundation

/// Invented status pages for SwiftUI previews, screenshots and the demo mode.
/// Nothing here describes a real deployment.
public enum SampleData {
    public enum Scenario: String, CaseIterable, Sendable {
        /// Fifteen monitors in four groups, everything up.
        case healthy
        /// The same page with two monitors down and a maintenance notice.
        case outage
        /// A single ungrouped monitor.
        case single
        /// Sixty-four monitors in six groups, one down.
        case large
    }

    public static func snapshot(_ scenario: Scenario, now: Date = Date()) -> StatusSnapshot {
        let nowSeconds = Int(now.timeIntervalSince1970)
        switch scenario {
        case .healthy:
            return page(groups: standardGroups, down: [:], now: nowSeconds, maintenance: false)
        case .outage:
            return page(
                groups: standardGroups,
                down: [
                    "payments-api": (minutes: 42, error: "HTTP 503 Service Unavailable"),
                    "eu-edge": (minutes: 7, error: "Timeout after 10000ms"),
                ],
                now: nowSeconds,
                maintenance: true
            )
        case .single:
            return page(groups: [("", [("homepage", "Homepage")])], down: [:], now: nowSeconds, maintenance: false)
        case .large:
            return page(
                groups: largeGroups,
                down: ["node-30": (minutes: 190, error: "Connection refused")],
                now: nowSeconds,
                maintenance: false
            )
        }
    }

    private static let standardGroups: [(String, [(String, String)])] = [
        ("Website", [("homepage", "Homepage"), ("docs", "Documentation"), ("blog", "Blog"), ("store", "Store")]),
        ("APIs", [
            ("public-api", "Public API"), ("payments-api", "Payments API"),
            ("auth", "Sign-in service"), ("webhooks", "Webhook delivery"),
        ]),
        ("Infrastructure", [
            ("database", "Database primary"), ("replica", "Database replica"), ("cache", "Cache cluster"),
            ("queue", "Job queue"), ("backup", "Nightly backup heartbeat"),
        ]),
        ("Edge", [("us-edge", "US edge"), ("eu-edge", "EU edge")]),
    ]

    private static var largeGroups: [(String, [(String, String)])] {
        let names: [(String, String, Int)] = [
            ("Storefronts", "shop", 10), ("Services", "svc", 12), ("Compute nodes", "node", 20),
            ("Databases", "db", 8), ("Regions", "region", 8), ("Internal tools", "tool", 6),
        ]
        var counter = 0
        return names.map { group, prefix, count in
            (group, (1...count).map { _ in
                counter += 1
                return ("\(prefix)-\(counter)", "\(prefix.capitalized) \(counter)")
            })
        }
    }

    private static func page(
        groups: [(String, [(String, String)])],
        down: [String: (minutes: Int, error: String)],
        now: Int,
        maintenance: Bool
    ) -> StatusSnapshot {
        var random = SeededGenerator(seed: 20_240_601)
        let locations = ["SEA", "FRA", "NRT", "IAD", "SYD"]
        var monitors: [Monitor] = []
        for (_, members) in groups {
            for (id, name) in members {
                let begin = now - 90 * 86_400
                var incidents = [Incident(starts: [begin], end: begin, errors: ["dummy"])]
                // A few short historical outages for some monitors.
                let outageCount = Int.random(in: 0...3, using: &random) == 0 ? Int.random(in: 1...4, using: &random) : 0
                var starts: [Int] = (0..<outageCount).map { _ in
                    now - Int.random(in: 2...88, using: &random) * 86_400 - Int.random(in: 0...80_000, using: &random)
                }
                starts.sort()
                for start in starts {
                    let length = Int.random(in: 4...180, using: &random) * 60
                    incidents.append(Incident(
                        starts: [start], end: start + length,
                        errors: [["HTTP 502 Bad Gateway", "Timeout after 10000ms", "Connection reset"]
                            .randomElement(using: &random)!]))
                }
                if let outage = down[id] {
                    let start = now - outage.minutes * 60
                    incidents.append(Incident(starts: [start], end: nil, errors: [outage.error]))
                }
                let heartbeat = id == "backup"
                let base = heartbeat ? 40 : Int.random(in: 35...420, using: &random)
                let location = locations.randomElement(using: &random)!
                var latency: [LatencyPoint] = []
                var time = now - 12 * 3600
                while time <= now - 30 {
                    let wobble = Double.random(in: -0.18...0.22, using: &random)
                    let spike = Int.random(in: 0...40, using: &random) == 0 ? Double.random(in: 1.5...3, using: &random) : 1
                    latency.append(LatencyPoint(
                        time: time,
                        ping: heartbeat ? Int.random(in: 5...55, using: &random) : max(8, Int(Double(base) * (1 + wobble) * spike)),
                        location: heartbeat ? "push" : location))
                    time += 180
                }
                monitors.append(Monitor(
                    id: id, name: name,
                    tooltip: id == "public-api" ? "Checks the /health route every minute" : nil,
                    incidents: incidents, latency: latency))
            }
        }
        let grouped = groups.count > 1 || !(groups.first?.0.isEmpty ?? true)
        let nowDate = Date(timeIntervalSince1970: TimeInterval(now))
        return StatusSnapshot(
            title: "Example Status",
            lastUpdate: now - 20,
            monitors: monitors,
            groups: grouped ? groups.map { MonitorGroup(name: $0.0, monitorIDs: $0.1.map(\.0)) } : [],
            maintenances: maintenance
                ? [Maintenance(
                    title: "Database upgrade",
                    body: "The replica is being upgraded. Read queries may be slower than usual.",
                    start: nowDate.addingTimeInterval(-1800), end: nowDate.addingTimeInterval(5400),
                    monitorIDs: ["replica"])]
                : [],
            format: .compacted,
            buildID: "sample"
        )
    }
}

/// A small deterministic generator so previews and screenshots are stable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
