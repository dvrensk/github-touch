import XCTest
@testable import GitHubTouchCore

final class CapabilityProberTests: XCTestCase {
    var prober: CapabilityProber!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        prober = CapabilityProber(session: URLSession(configuration: config))
    }

    func route(_ responses: [String: (Int, [String: String], String)]) {
        MockURLProtocol.handler = { request in
            let path = request.url!.path
            let (status, headers, body) = responses[path] ?? (404, [:], "{}")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: headers)!
            return (response, Data(body.utf8))
        }
    }

    func testAllGrantedWithRepoNames() async throws {
        route([
            "/user/repos": (200, [:], #"""
                [{"name":"api","private":true},
                 {"name":"web","private":true,"visibility":"private"},
                 {"name":"infra","private":false,"visibility":"internal"}]
                """#),
            "/user/orgs": (200, [:], "[]"),
            "/gists": (200, [:], "[]"),
            "/notifications": (200, [:], "[]"),
            "/user/emails": (200, [:], "[]"),
        ])
        let report = try await prober.probe("tok123")
        XCTAssertEqual(report.repos, .granted(detail: ["api", "web", "infra"]))
        XCTAssertEqual(report.orgs, .granted(detail: nil))
        XCTAssertEqual(report.emails, .granted(detail: nil))
    }

    func testPublicReposAreFilteredOut() async throws {
        // Fine-grained tokens can read all public repos regardless of grants,
        // so /user/repos includes them; only non-public entries prove access.
        route([
            "/user/repos": (200, [:], #"""
                [{"name":"blog","private":false,"visibility":"public"},
                 {"name":"secret","private":true,"visibility":"private"},
                 {"name":"dotfiles","private":false}]
                """#),
            "/user/orgs": (200, [:], "[]"),
            "/gists": (200, [:], "[]"),
            "/notifications": (200, [:], "[]"),
            "/user/emails": (200, [:], "[]"),
        ])
        let report = try await prober.probe("tok123")
        XCTAssertEqual(report.repos, .granted(detail: ["secret"]))
    }

    func testOnlyPublicReposYieldsEmptyGrant() async throws {
        route([
            "/user/repos": (200, [:], #"""
                [{"name":"blog","private":false,"visibility":"public"},
                 {"name":"talks","private":false,"visibility":"public"}]
                """#),
            "/user/orgs": (200, [:], "[]"),
            "/gists": (200, [:], "[]"),
            "/notifications": (200, [:], "[]"),
            "/user/emails": (200, [:], "[]"),
        ])
        let report = try await prober.probe("tok123")
        XCTAssertEqual(report.repos, .granted(detail: []))
    }

    func testDeniedRecordsNeededPermissionsHeader() async throws {
        route([
            "/user/repos": (200, [:], "[]"),
            "/user/orgs": (403, ["X-Accepted-GitHub-Permissions": "members=read"], "{}"),
            "/gists": (403, [:], "{}"),
            "/notifications": (200, [:], "[]"),
            "/user/emails": (200, [:], "[]"),
        ])
        let report = try await prober.probe("tok123")
        XCTAssertEqual(report.orgs, .denied(needed: "members=read"))
        XCTAssertEqual(report.gists, .denied(needed: nil))
        XCTAssertEqual(report.repos, .granted(detail: []))
    }

    func testUnexpectedStatusIsUnknown() async throws {
        route([
            "/user/repos": (500, [:], "{}"),
            "/user/orgs": (200, [:], "[]"),
            "/gists": (200, [:], "[]"),
            "/notifications": (200, [:], "[]"),
            "/user/emails": (200, [:], "[]"),
        ])
        let report = try await prober.probe("tok123")
        XCTAssertEqual(report.repos, .unknown)
    }

    func testAnyUnauthorizedThrowsInvalidToken() async {
        route([
            "/user/repos": (401, [:], "{}"),
            "/user/orgs": (200, [:], "[]"),
            "/gists": (200, [:], "[]"),
            "/notifications": (200, [:], "[]"),
            "/user/emails": (200, [:], "[]"),
        ])
        do {
            _ = try await prober.probe("tok123")
            XCTFail("should throw")
        } catch let error as TokenValidationError {
            XCTAssertEqual(error, .invalidToken)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
