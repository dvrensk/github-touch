import XCTest
@testable import GitHubTouchCore

final class ScopeCatalogTests: XCTestCase {
    func testKnownScopes() {
        XCTAssertEqual(ScopeCatalog.describe("repo").phrase, "read/write ALL repos")
        XCTAssertTrue(ScopeCatalog.describe("repo").dangerous)
        XCTAssertEqual(ScopeCatalog.describe("gist").phrase, "gists")
        XCTAssertFalse(ScopeCatalog.describe("gist").dangerous)
        XCTAssertTrue(ScopeCatalog.describe("delete_repo").dangerous)
        XCTAssertTrue(ScopeCatalog.describe("admin:org").dangerous)
        XCTAssertFalse(ScopeCatalog.describe("read:org").dangerous)
    }

    func testUnknownScopePassesThroughVerbatim() {
        let result = ScopeCatalog.describe("codespace")
        XCTAssertEqual(result.phrase, "codespace")
        XCTAssertFalse(result.dangerous)
    }
}
