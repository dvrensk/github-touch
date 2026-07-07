import XCTest
@testable import GitHubTouchCore

final class TokenURLBuilderTests: XCTestCase {
    func testClassicURLEncodesScopesAndDescription() {
        let url = TokenURLBuilder.classicNewTokenURL(
            scopes: ["repo", "read:org"], description: "CI helper & tools")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/settings/tokens/new")
        let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["scopes"], "repo,read:org")
        XCTAssertEqual(query["description"], "CI helper & tools")
    }

    func testFineGrainedURL() {
        XCTAssertEqual(TokenURLBuilder.fineGrainedNewTokenURL.absoluteString,
                       "https://github.com/settings/personal-access-tokens/new")
    }
}
