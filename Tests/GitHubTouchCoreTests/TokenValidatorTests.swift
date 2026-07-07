import XCTest
@testable import GitHubTouchCore

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (response, data) = Self.handler!(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class TokenValidatorTests: XCTestCase {
    var validator: TokenValidator!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        validator = TokenValidator(session: URLSession(configuration: config))
    }

    func respond(status: Int, headers: [String: String] = [:], body: String = #"{"login":"dvrensk"}"#) {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/user")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: headers)!
            return (response, Data(body.utf8))
        }
    }

    func testClassicTokenScopesAndExpiry() async throws {
        respond(status: 200, headers: [
            "X-OAuth-Scopes": "repo, gist, read:org",
            "GitHub-Authentication-Token-Expiration": "2026-10-01 07:00:00 UTC",
        ])
        let info = try await validator.validate("tok123")
        XCTAssertEqual(info.login, "dvrensk")
        XCTAssertEqual(info.scopes, ["repo", "gist", "read:org"])
        let expected = ISO8601DateFormatter().date(from: "2026-10-01T07:00:00Z")
        XCTAssertEqual(info.expiresAt, expected)
    }

    func testFineGrainedTokenHasNoScopes() async throws {
        respond(status: 200)
        let info = try await validator.validate("tok123")
        XCTAssertNil(info.scopes)
        XCTAssertNil(info.expiresAt)
    }

    func testEmptyScopesHeaderMeansNoScopes() async throws {
        respond(status: 200, headers: ["X-OAuth-Scopes": ""])
        let info = try await validator.validate("tok123")
        XCTAssertNil(info.scopes)
    }

    func testBadTokenThrowsInvalid() async {
        respond(status: 401, body: #"{"message":"Bad credentials"}"#)
        do {
            _ = try await validator.validate("tok123")
            XCTFail("should throw")
        } catch let error as TokenValidationError {
            XCTAssertEqual(error, .invalidToken)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testParseExpirationFormats() {
        XCTAssertNotNil(TokenValidator.parseExpiration("2026-10-01 07:00:00 UTC"))
        XCTAssertNotNil(TokenValidator.parseExpiration("2026-10-01T07:00:00Z"))
        XCTAssertNil(TokenValidator.parseExpiration("never"))
    }
}
