import XCTest
@testable import GitHubTouchCore

final class DescriptionBuilderTests: XCTestCase {
    func testClassicScopesMapWithDangerFlags() {
        let result = DescriptionBuilder.build(kind: .classic, scopes: ["repo", "gist"],
                                              probe: nil, expiresAt: nil)
        XCTAssertEqual(result.summary, "⚠ read/write ALL repos, gists")
        XCTAssertEqual(result.details, ["⚠ read/write ALL repos", "gists"])
    }

    func testExpiryAppendedToDetails() {
        let expiry = Date(timeIntervalSince1970: 1_790_000_000)
        let result = DescriptionBuilder.build(kind: .oauth, scopes: ["gist"],
                                              probe: nil, expiresAt: expiry)
        let expected = "expires \(expiry.formatted(date: .abbreviated, time: .omitted))"
        XCTAssertEqual(result.details.last, expected)
        XCTAssertEqual(result.summary, "gists")
    }

    func testSummaryTruncatedAtWordBoundary() {
        let scopes = ["repo", "admin:org", "workflow", "delete_repo", "notifications"]
        let result = DescriptionBuilder.build(kind: .classic, scopes: scopes,
                                              probe: nil, expiresAt: nil)
        XCTAssertLessThanOrEqual(result.summary.count, 61)  // 60 + "…"
        XCTAssertTrue(result.summary.hasSuffix("…"))
        XCTAssertFalse(result.summary.contains("……"))
    }

    func testTruncateHelper() {
        XCTAssertEqual(DescriptionBuilder.truncate("short", to: 60), "short")
        XCTAssertEqual(DescriptionBuilder.truncate("one two three", to: 8), "one two…")
    }

    func testFineGrainedSummaryNamesRepos() {
        let probe = ProbeReport(repos: .granted(detail: ["api", "web", "infra", "docs", "ops"]),
                                orgs: .granted(detail: nil),
                                gists: .denied(needed: nil),
                                notifications: .unknown,
                                emails: .denied(needed: "email=read"))
        let result = DescriptionBuilder.build(kind: .fineGrained, scopes: nil,
                                              probe: probe, expiresAt: nil)
        XCTAssertEqual(result.summary, "repos: api, web (+3); orgs")
        XCTAssertEqual(result.details, [
            "repo access: api, web, infra, docs, ops",
            "org read access",
            "no gist access",
            "notifications access: probe failed",
            "no email access (needs: email=read)",
        ])
    }

    func testFineGrainedNothingGranted() {
        let probe = ProbeReport(repos: .denied(needed: nil), orgs: .denied(needed: nil),
                                gists: .denied(needed: nil), notifications: .denied(needed: nil),
                                emails: .denied(needed: nil))
        let result = DescriptionBuilder.build(kind: .fineGrained, scopes: nil,
                                              probe: probe, expiresAt: nil)
        XCTAssertEqual(result.summary, "no API read access found")
    }

    func testNoInputsYieldsEmpty() {
        let result = DescriptionBuilder.build(kind: .fineGrained, scopes: nil,
                                              probe: nil, expiresAt: nil)
        XCTAssertEqual(result.summary, "")
        XCTAssertEqual(result.details, [])
    }
}
