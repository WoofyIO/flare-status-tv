import Foundation

/// The parts of UptimeFlare's `pageConfig` that the status page shows but
/// does not send as data: the title and the monitor groups.
public struct PageConfigInfo: Equatable, Sendable, Codable {
    public var title: String?
    public var groups: [Group]

    public struct Group: Equatable, Sendable, Codable {
        public var name: String
        public var monitorIDs: [String]

        public init(name: String, monitorIDs: [String]) {
            self.name = name
            self.monitorIDs = monitorIDs
        }
    }

    public init(title: String?, groups: [Group]) {
        self.title = title
        self.groups = groups
    }
}

/// Reads `pageConfig` out of the status page's compiled JavaScript.
///
/// UptimeFlare has no API for the title or the groups; they are compiled into
/// one of the page's script files as an object literal such as
/// `{title:"My status",links:[...],group:{"Web":["site","api"],Infra:["db"]}}`.
/// This is a best-effort reader for that literal. When it finds nothing the
/// app simply shows the monitors ungrouped.
public enum PageConfigReader {
    public static func read(javascript: String, knownMonitorIDs: Set<String>) -> PageConfigInfo? {
        let source = Array(javascript.unicodeScalars)
        var best: (config: PageConfigInfo, matches: Int)?
        var searchFrom = 0
        while let index = find("group:", in: source, from: searchFrom) {
            searchFrom = index + 1
            var scanner = Scanner(source: source, position: index + "group:".count)
            guard let groups = scanner.parseGroupObject(), !groups.isEmpty else { continue }
            let matches = groups.flatMap(\.monitorIDs).filter(knownMonitorIDs.contains).count
            guard matches > 0 || knownMonitorIDs.isEmpty else { continue }
            if best == nil || matches > best!.matches {
                let title = titleBefore(index, in: source)
                best = (PageConfigInfo(title: title, groups: groups), matches)
            }
        }
        if let best { return best.config }
        return nil
    }

    /// Finds the title when the page has no groups: the `title:"..."` that
    /// sits next to `links:[` in the same literal.
    public static func readTitleOnly(javascript: String) -> String? {
        let source = Array(javascript.unicodeScalars)
        guard let links = find("links:[", in: source, from: 0) else { return nil }
        return titleBefore(links, in: source)
    }

    private static func titleBefore(_ index: Int, in source: [Unicode.Scalar]) -> String? {
        let windowStart = max(0, index - 6000)
        var found: String?
        var from = windowStart
        while let at = find("title:", in: source, from: from), at < index {
            from = at + 1
            var scanner = Scanner(source: source, position: at + "title:".count)
            if let text = scanner.parseString() { found = text }
        }
        return found
    }

    private static func find(_ needle: String, in source: [Unicode.Scalar], from: Int) -> Int? {
        let pattern = Array(needle.unicodeScalars)
        guard !pattern.isEmpty, source.count >= pattern.count, from <= source.count - pattern.count else { return nil }
        var i = from
        let last = source.count - pattern.count
        while i <= last {
            if source[i] == pattern[0] {
                var j = 1
                while j < pattern.count, source[i + j] == pattern[j] { j += 1 }
                if j == pattern.count { return i }
            }
            i += 1
        }
        return nil
    }

    /// A very small reader for JavaScript object, array and string literals.
    struct Scanner {
        let source: [Unicode.Scalar]
        var position: Int

        mutating func skipWhitespace() {
            while position < source.count, source[position].properties.isWhitespace { position += 1 }
        }

        mutating func consume(_ scalar: Unicode.Scalar) -> Bool {
            skipWhitespace()
            guard position < source.count, source[position] == scalar else { return false }
            position += 1
            return true
        }

        /// `{ key: ["a", "b"], "other key": [...] }`
        mutating func parseGroupObject() -> [PageConfigInfo.Group]? {
            guard consume("{") else { return nil }
            var groups: [PageConfigInfo.Group] = []
            while true {
                if consume("}") { return groups }
                guard let key = parseKey(), consume(":"), let values = parseStringArray() else { return nil }
                groups.append(.init(name: key, monitorIDs: values))
                if consume(",") { continue }
                return consume("}") ? groups : nil
            }
        }

        mutating func parseStringArray() -> [String]? {
            guard consume("[") else { return nil }
            var values: [String] = []
            while true {
                if consume("]") { return values }
                guard let value = parseString() else { return nil }
                values.append(value)
                if consume(",") { continue }
                return consume("]") ? values : nil
            }
        }

        mutating func parseKey() -> String? {
            skipWhitespace()
            guard position < source.count else { return nil }
            let first = source[position]
            if first == "\"" || first == "'" || first == "`" { return parseString() }
            var name = String.UnicodeScalarView()
            while position < source.count {
                let c = source[position]
                let allowed = c == "_" || c == "$" || c.properties.isAlphabetic
                    || (c.properties.numericType != nil) || c.value > 0x7F
                guard allowed else { break }
                name.append(c)
                position += 1
            }
            return name.isEmpty ? nil : String(name)
        }

        mutating func parseString() -> String? {
            skipWhitespace()
            guard position < source.count else { return nil }
            let quote = source[position]
            guard quote == "\"" || quote == "'" || quote == "`" else { return nil }
            position += 1
            var out = String.UnicodeScalarView()
            while position < source.count {
                let c = source[position]
                position += 1
                if c == quote { return String(out) }
                if c == "\n" && quote != "`" { return nil }
                guard c == "\\" else {
                    out.append(c)
                    continue
                }
                guard position < source.count else { return nil }
                let escaped = source[position]
                position += 1
                switch escaped {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "b", "f", "v", "0": break
                case "x":
                    guard let scalar = hexScalar(digits: 2) else { return nil }
                    out.append(scalar)
                case "u":
                    if position < source.count, source[position] == "{" {
                        position += 1
                        var digits = 0
                        var value: UInt32 = 0
                        while position < source.count, source[position] != "}" {
                            guard let d = hexValue(source[position]), digits < 6 else { return nil }
                            value = value * 16 + d
                            digits += 1
                            position += 1
                        }
                        position += 1
                        guard let scalar = Unicode.Scalar(value) else { return nil }
                        out.append(scalar)
                    } else {
                        guard let unit = hexUnit(digits: 4) else { return nil }
                        if (0xD800...0xDBFF).contains(unit),
                           position + 1 < source.count, source[position] == "\\", source[position + 1] == "u" {
                            position += 2
                            guard let low = hexUnit(digits: 4), (0xDC00...0xDFFF).contains(low) else { return nil }
                            let combined = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                            guard let scalar = Unicode.Scalar(combined) else { return nil }
                            out.append(scalar)
                        } else {
                            guard let scalar = Unicode.Scalar(unit) else { return nil }
                            out.append(scalar)
                        }
                    }
                default: out.append(escaped)
                }
            }
            return nil
        }

        private mutating func hexUnit(digits: Int) -> UInt32? {
            guard position + digits <= source.count else { return nil }
            var value: UInt32 = 0
            for _ in 0..<digits {
                guard let d = hexValue(source[position]) else { return nil }
                value = value * 16 + d
                position += 1
            }
            return value
        }

        private mutating func hexScalar(digits: Int) -> Unicode.Scalar? {
            hexUnit(digits: digits).flatMap(Unicode.Scalar.init)
        }

        private func hexValue(_ c: Unicode.Scalar) -> UInt32? {
            switch c.value {
            case 48...57: return c.value - 48
            case 97...102: return c.value - 87
            case 65...70: return c.value - 55
            default: return nil
            }
        }
    }
}
