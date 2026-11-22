import Foundation
import XCTest
@testable import FlareStatusKit

/// The fixed "now" the fixtures were generated for (scripts/make-fixtures.mjs).
let fixtureNow = 1_780_000_000

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
            "missing fixture \(name)")
        return try Data(contentsOf: url)
    }

    static func text(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
    }
}

/// Serves canned responses by path and records what was asked for.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    var routes: [String: HTTPResult] = [:]
    var failure: Error?
    private(set) var requests: [(path: String, headers: [String: String])] = []
    private let lock = NSLock()

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResult {
        lock.withLock { requests.append((url.path, headers)) }
        if let failure { throw failure }
        return routes[url.path] ?? HTTPResult(status: 404, body: Data("not found".utf8))
    }

    var requestedPaths: [String] { requests.map(\.path) }
}
