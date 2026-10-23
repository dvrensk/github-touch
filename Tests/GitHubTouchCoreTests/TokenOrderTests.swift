import XCTest
@testable import GitHubTouchCore

final class TokenOrderTests: XCTestCase {
    func entry(_ label: String, _ tag: TokenTag?) -> TokenEntry {
        TokenEntry(id: UUID(), label: label, kind: .classic, permissions: [], expiresAt: nil,
                   createdAt: Date(timeIntervalSince1970: 0), lastActivatedAt: nil, notes: "",
                   ephemeralPub: Data(), ciphertext: Data(), tag: tag)
    }

    func testSortedByTagIsNoneGreenOrangeRedKeepingVaultOrderWithinATag() {
        let tokens = [entry("r1", .red), entry("g1", .green), entry("n1", nil),
                      entry("o1", .orange), entry("g2", .green), entry("n2", nil), entry("r2", .red)]
        XCTAssertEqual(tokens.sortedByTag().map(\.label),
                       ["n1", "n2", "g1", "g2", "o1", "r1", "r2"])
    }
}
