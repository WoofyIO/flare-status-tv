import Foundation

/// Why a status page could not be loaded, in terms a person can act on.
public enum StatusError: Error, Equatable, Sendable {
    case invalidAddress(String)
    case offline(String)
    case authenticationRequired
    case authenticationFailed
    case notUptimeFlare(String)
    case noDataYet
    case server(Int)
    case malformed(String)

    public var title: String {
        switch self {
        case .invalidAddress: return "That address is not valid"
        case .offline: return "Cannot reach the status page"
        case .authenticationRequired: return "This status page needs a password"
        case .authenticationFailed: return "The user name or password was not accepted"
        case .notUptimeFlare: return "This is not an UptimeFlare status page"
        case .noDataYet: return "The status page has no data yet"
        case .server(let code): return "The status page answered with an error (HTTP \(code))"
        case .malformed: return "The status page sent data this app cannot read"
        }
    }

    public var detail: String {
        switch self {
        case .invalidAddress(let reason): return reason
        case .offline(let reason): return reason
        case .authenticationRequired:
            return "Enter the user name and password from the deployment's passwordProtection setting."
        case .authenticationFailed:
            return "Check the user name and password. They are the two halves of passwordProtection (\"user:password\")."
        case .notUptimeFlare(let reason): return reason
        case .noDataYet: return "The UptimeFlare worker has not completed its first check. Try again in a minute."
        case .server: return "The deployment may be starting up or misconfigured. The app will keep trying."
        case .malformed(let reason): return reason
        }
    }
}

public struct Credentials: Equatable, Sendable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /// UptimeFlare compares the header with `"Basic " + btoa(passwordProtection)`,
    /// where passwordProtection is "username:password".
    public var authorizationHeader: String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }
}

public enum PageAddress {
    /// Turns what a person typed ("status.example.com", "https://status.example.com/incidents")
    /// into the root URL of the status page.
    public static func normalize(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw StatusError.invalidAddress("Enter the address of the status page.") }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty
        else {
            throw StatusError.invalidAddress("Use an address like status.example.com.")
        }
        guard scheme == "https" || scheme == "http" else {
            throw StatusError.invalidAddress("Only http and https addresses are supported.")
        }
        guard !host.contains(" "), host.contains(".") || host == "localhost" || host.contains(":") else {
            throw StatusError.invalidAddress("Use an address like status.example.com.")
        }
        components.scheme = scheme
        components.host = host.lowercased()
        components.path = "/"
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        guard let url = components.url else {
            throw StatusError.invalidAddress("Use an address like status.example.com.")
        }
        return url
    }
}

public struct HTTPResult: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// `max-age` from Cache-Control, if the server sent one.
    public var maxAge: Int? {
        guard let value = headers.first(where: { $0.key.lowercased() == "cache-control" })?.value else { return nil }
        for directive in value.split(separator: ",") {
            let parts = directive.trimmingCharacters(in: .whitespaces).split(separator: "=")
            if parts.count == 2, parts[0].lowercased() == "max-age", let seconds = Int(parts[1]) { return seconds }
        }
        return nil
    }
}

public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResult
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        var fields: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { fields[key] = value }
        }
        return HTTPResult(status: http.statusCode, headers: fields, body: data)
    }
}

/// Reads one UptimeFlare deployment.
///
/// - `fetchFull()` loads the status page itself (the only place the monitor
///   names and the history are published) and `/api/data`.
/// - `fetchLive()` loads only `/api/data`, a few kilobytes, for the frequent
///   refresh in between.
public struct StatusClient: Sendable {
    public let baseURL: URL
    public let credentials: Credentials?
    private let transport: HTTPTransport

    public init(baseURL: URL, credentials: Credentials? = nil, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.transport = transport
    }

    public struct FullResult: Sendable {
        public var snapshot: StatusSnapshot
        /// The page configuration that was used, to pass back in next time.
        public var config: CachedConfig?
        /// The longest max-age any response asked for.
        public var maxAge: Int?
    }

    /// The title and groups read from a specific build of the page.
    public struct CachedConfig: Equatable, Sendable, Codable {
        public var buildID: String
        public var info: PageConfigInfo?

        public init(buildID: String, info: PageConfigInfo?) {
            self.buildID = buildID
            self.info = info
        }
    }

    public func fetchFull(cachedConfig: CachedConfig? = nil) async throws -> FullResult {
        let page = try await get(baseURL)
        guard let html = String(data: page.body, encoding: .utf8) else {
            throw StatusError.notUptimeFlare("The page is not text.")
        }
        let payload: PagePayload
        do {
            payload = try PageParser.parse(html: html)
        } catch let failure as DecodingFailure {
            throw StatusClient.map(failure)
        }
        var snapshot = payload.snapshot
        var maxAge = page.maxAge

        // Title and groups: reuse what was read from this build, else look
        // through the page's scripts once.
        var config = cachedConfig
        if let buildID = payload.buildID {
            if config?.buildID != buildID {
                let info = await readConfig(html: html, monitorIDs: Set(snapshot.monitors.map(\.id)))
                config = CachedConfig(buildID: buildID, info: info)
            }
        } else {
            config = nil
        }
        if let info = config?.info {
            snapshot.title = info.title
            snapshot.groups = info.groups.map { MonitorGroup(name: $0.name, monitorIDs: $0.monitorIDs) }
        }

        // Maintenances are only published by /api/data. The page already
        // loaded, so a failure here is not fatal.
        if let live = try? await fetchLiveResult() {
            snapshot = snapshot.applying(live.data).snapshot
            maxAge = [maxAge, live.maxAge].compactMap { $0 }.max()
        }
        return FullResult(snapshot: snapshot, config: config, maxAge: maxAge)
    }

    public struct LiveResult: Sendable {
        public var data: LiveData
        public var maxAge: Int?
    }

    public func fetchLive() async throws -> LiveResult {
        try await fetchLiveResult()
    }

    private func fetchLiveResult() async throws -> LiveResult {
        let url = baseURL.appendingPathComponent("api/data")
        let result = try await get(url, acceptStatuses: [200, 500])
        do {
            let data = try LiveData.parse(result.body)
            return LiveResult(data: data, maxAge: result.maxAge)
        } catch let failure as DecodingFailure {
            if result.status != 200, failure != .noDataYet { throw StatusError.server(result.status) }
            throw StatusClient.map(failure)
        }
    }

    private func readConfig(html: String, monitorIDs: Set<String>) async -> PageConfigInfo? {
        let sources = PageParser.scriptSources(in: html).filter {
            $0.contains("/_next/static/chunks/")
                && !$0.contains("polyfills") && !$0.contains("framework") && !$0.contains("webpack")
                && !$0.contains("/main-")
        }
        var titleOnly: String?
        // The configuration normally lives in a small shared chunk; the page
        // lists at most a dozen scripts.
        for source in sources.prefix(16) {
            guard let url = URL(string: source, relativeTo: baseURL)?.absoluteURL,
                  url.host == baseURL.host,
                  let result = try? await get(url),
                  let script = String(data: result.body, encoding: .utf8)
            else { continue }
            if let info = PageConfigReader.read(javascript: script, knownMonitorIDs: monitorIDs) {
                return info
            }
            if titleOnly == nil, script.contains("links:[") {
                titleOnly = PageConfigReader.readTitleOnly(javascript: script)
            }
        }
        return titleOnly.map { PageConfigInfo(title: $0, groups: []) }
    }

    private func get(_ url: URL, acceptStatuses: Set<Int> = [200]) async throws -> HTTPResult {
        var headers = ["Accept": "text/html,application/json;q=0.9,*/*;q=0.8"]
        if let credentials { headers["Authorization"] = credentials.authorizationHeader }
        let result: HTTPResult
        do {
            result = try await transport.get(url, headers: headers)
        } catch let error as StatusError {
            throw error
        } catch {
            throw StatusError.offline(StatusClient.describe(error))
        }
        if result.status == 401 || result.status == 403 {
            throw credentials == nil ? StatusError.authenticationRequired : StatusError.authenticationFailed
        }
        guard acceptStatuses.contains(result.status) else { throw StatusError.server(result.status) }
        return result
    }

    static func map(_ failure: DecodingFailure) -> StatusError {
        switch failure {
        case .notUptimeFlare(let reason): return .notUptimeFlare(reason)
        case .noDataYet: return .noDataYet
        case .malformedState(let reason): return .malformed(reason)
        }
    }

    static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "The Apple TV is not connected to the network."
        case .cannotFindHost, .dnsLookupFailed:
            return "No server was found at that address. Check the spelling."
        case .timedOut:
            return "The server took too long to answer."
        case .cannotConnectToHost:
            return "The server refused the connection."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return "A secure connection could not be made (certificate problem)."
        case .appTransportSecurityRequiresSecureConnection:
            return "Plain http is only allowed for addresses on the local network. Use https."
        default:
            return urlError.localizedDescription
        }
    }
}
