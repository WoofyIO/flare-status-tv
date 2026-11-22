import XCTest
@testable import FlareStatusKit

final class StatusClientTests: XCTestCase {
    private let base = URL(string: "https://status.example.com/")!

    private func stockTransport() throws -> StubTransport {
        let transport = StubTransport()
        transport.routes["/"] = HTTPResult(status: 200, body: try Fixture.data("page-d1.html"))
        transport.routes["/api/data"] = HTTPResult(
            status: 200, headers: ["Cache-Control": "public, max-age=120"], body: try Fixture.data("api-data.json"))
        transport.routes["/_next/static/chunks/469-5555.js"] = HTTPResult(status: 200, body: try Fixture.data("config-chunk.js"))
        transport.routes["/_next/static/chunks/pages/index-6666.js"] = HTTPResult(status: 200, body: Data("console.log(1)".utf8))
        transport.routes["/_next/static/chunks/pages/_app-4444.js"] = HTTPResult(status: 200, body: Data("console.log(2)".utf8))
        return transport
    }

    func testFullFetchCombinesPageConfigAndLiveData() async throws {
        let transport = try stockTransport()
        let client = StatusClient(baseURL: base, transport: transport)
        let result = try await client.fetchFull()

        XCTAssertEqual(result.snapshot.title, "Example \u{2014} Status")
        XCTAssertEqual(result.snapshot.sections.map(\.name), ["Website", "APIs & data", "Caf\u{e9}"])
        XCTAssertEqual(result.snapshot.maintenances.count, 2)
        XCTAssertEqual(result.snapshot.lastUpdate, fixtureNow)
        XCTAssertEqual(result.maxAge, 120)
        XCTAssertEqual(result.config?.buildID, "fixtureBuild01")
        XCTAssertFalse(transport.requestedPaths.contains { $0.contains("framework") || $0.contains("polyfills") })
        XCTAssertNil(transport.requests[0].headers["Authorization"])

        // The same build again: the scripts are not downloaded a second time.
        let before = transport.requestedPaths.count
        let again = try await client.fetchFull(cachedConfig: result.config)
        XCTAssertEqual(again.snapshot.groups, result.snapshot.groups)
        XCTAssertEqual(transport.requestedPaths.count - before, 2)
    }

    func testFullFetchSurvivesMissingConfigAndAPI() async throws {
        let transport = StubTransport()
        transport.routes["/"] = HTTPResult(status: 200, body: try Fixture.data("page-kv-legacy.html"))
        let result = try await StatusClient(baseURL: base, transport: transport).fetchFull()
        XCTAssertEqual(result.snapshot.format, .legacy)
        XCTAssertTrue(result.snapshot.groups.isEmpty)
        XCTAssertNil(result.snapshot.title)
        XCTAssertEqual(result.snapshot.monitors.count, 4)
        XCTAssertEqual(result.snapshot.sections.count, 1)
    }

    func testLiveFetch() async throws {
        let client = StatusClient(baseURL: base, transport: try stockTransport())
        let live = try await client.fetchLive()
        XCTAssertEqual(live.data.down, 1)
        XCTAssertEqual(live.maxAge, 120)
    }

    func testPasswordProtection() async throws {
        let transport = StubTransport()
        transport.routes["/"] = HTTPResult(
            status: 401, headers: ["WWW-Authenticate": "Basic"], body: Data(#"{"code":401,"message":"Not authenticated"}"#.utf8))

        await assertThrows(StatusError.authenticationRequired) {
            _ = try await StatusClient(baseURL: self.base, transport: transport).fetchFull()
        }
        let credentials = Credentials(username: "admin", password: "s3cret")
        await assertThrows(StatusError.authenticationFailed) {
            _ = try await StatusClient(baseURL: self.base, credentials: credentials, transport: transport).fetchFull()
        }
        // UptimeFlare expects "Basic " + btoa("username:password").
        XCTAssertEqual(credentials.authorizationHeader, "Basic YWRtaW46czNjcmV0")
        XCTAssertEqual(transport.requests.last?.headers["Authorization"], "Basic YWRtaW46czNjcmV0")
    }

    func testErrorsAreExplained() async throws {
        let transport = StubTransport()
        transport.routes["/"] = HTTPResult(status: 200, body: try Fixture.data("page-not-nextjs.html"))
        await assertThrows({ if case .notUptimeFlare = $0 { return true } else { return false } }) {
            _ = try await StatusClient(baseURL: self.base, transport: transport).fetchFull()
        }

        transport.routes["/"] = HTTPResult(status: 200, body: try Fixture.data("page-no-state.html"))
        await assertThrows(StatusError.noDataYet) {
            _ = try await StatusClient(baseURL: self.base, transport: transport).fetchFull()
        }

        transport.routes["/"] = HTTPResult(status: 200, body: try Fixture.data("page-d1-corrupt.html"))
        await assertThrows({ if case .malformed = $0 { return true } else { return false } }) {
            _ = try await StatusClient(baseURL: self.base, transport: transport).fetchFull()
        }

        transport.routes["/"] = HTTPResult(status: 503, body: Data())
        await assertThrows(StatusError.server(503)) {
            _ = try await StatusClient(baseURL: self.base, transport: transport).fetchFull()
        }

        transport.routes["/api/data"] = HTTPResult(status: 500, body: try Fixture.data("api-no-data.json"))
        await assertThrows(StatusError.noDataYet) {
            _ = try await StatusClient(baseURL: self.base, transport: transport).fetchLive()
        }
        transport.routes["/api/data"] = HTTPResult(status: 500, body: Data("Internal Server Error".utf8))
        await assertThrows(StatusError.server(500)) {
            _ = try await StatusClient(baseURL: self.base, transport: transport).fetchLive()
        }

        transport.failure = URLError(.cannotFindHost)
        await assertThrows({ if case .offline(let reason) = $0 { return reason.contains("No server") } else { return false } }) {
            _ = try await StatusClient(baseURL: self.base, transport: transport).fetchFull()
        }
    }

    func testAddressNormalization() throws {
        XCTAssertEqual(try PageAddress.normalize("status.example.com").absoluteString, "https://status.example.com/")
        XCTAssertEqual(try PageAddress.normalize("  HTTPS://Status.Example.com/incidents?x=1#web ").absoluteString, "https://status.example.com/")
        XCTAssertEqual(try PageAddress.normalize("http://192.168.1.20:3000").absoluteString, "http://192.168.1.20:3000/")
        XCTAssertEqual(try PageAddress.normalize("localhost:8787").absoluteString, "https://localhost:8787/")
        XCTAssertEqual(try PageAddress.normalize("https://user:pw@status.example.com").absoluteString, "https://status.example.com/")
        for bad in ["", "   ", "ftp://status.example.com", "not a url", "status", "https://"] {
            XCTAssertThrowsError(try PageAddress.normalize(bad), bad) { error in
                guard case .invalidAddress? = error as? StatusError else { return XCTFail("\(bad): \(error)") }
            }
        }
    }

    func testCacheControlParsing() {
        XCTAssertEqual(HTTPResult(status: 200, headers: ["cache-control": "max-age=30"], body: Data()).maxAge, 30)
        XCTAssertEqual(HTTPResult(status: 200, headers: ["Cache-Control": "no-store, max-age=0, must-revalidate"], body: Data()).maxAge, 0)
        XCTAssertNil(HTTPResult(status: 200, headers: ["Cache-Control": "no-store"], body: Data()).maxAge)
        XCTAssertNil(HTTPResult(status: 200, body: Data()).maxAge)
    }

    private func assertThrows(
        _ expected: StatusError, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> Void
    ) async {
        await assertThrows({ $0 == expected }, file: file, line: line, body)
    }

    private func assertThrows(
        _ matches: (StatusError) -> Bool, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected an error", file: file, line: line)
        } catch let error as StatusError {
            XCTAssertTrue(matches(error), "unexpected \(error)", file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }
}
