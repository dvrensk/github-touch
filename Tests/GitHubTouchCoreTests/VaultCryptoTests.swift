import CryptoKit
import XCTest
@testable import GitHubTouchCore

final class VaultCryptoTests: XCTestCase {
    func testSealUnsealRoundTrip() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let (eph, ct) = try VaultCrypto.seal("ghp_secret123", recipientPub: key.x963PublicKey)
        let out = try VaultCrypto.unseal(ciphertext: ct, ephemeralPub: eph, using: key)
        XCTAssertEqual(out, "ghp_secret123")
    }

    func testTokensAreSealedIndependently() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let a = try VaultCrypto.seal("token-a", recipientPub: key.x963PublicKey)
        let b = try VaultCrypto.seal("token-b", recipientPub: key.x963PublicKey)
        XCTAssertNotEqual(a.ephemeralPub, b.ephemeralPub)
        XCTAssertEqual(try VaultCrypto.unseal(ciphertext: a.ciphertext, ephemeralPub: a.ephemeralPub, using: key), "token-a")
        XCTAssertEqual(try VaultCrypto.unseal(ciphertext: b.ciphertext, ephemeralPub: b.ephemeralPub, using: key), "token-b")
    }

    func testUnsealWithWrongKeyThrows() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let other = P256.KeyAgreement.PrivateKey()
        let (eph, ct) = try VaultCrypto.seal("secret", recipientPub: key.x963PublicKey)
        XCTAssertThrowsError(try VaultCrypto.unseal(ciphertext: ct, ephemeralPub: eph, using: other))
    }

    func testVaultFileCodableRoundTrip() throws {
        let entry = TokenEntry(
            id: UUID(), label: "repo read-only", kind: .fineGrained,
            permissions: ["contents: read", "metadata: read"],
            expiresAt: Date(timeIntervalSince1970: 1_790_000_000),
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            lastActivatedAt: nil, notes: "for CI tools",
            ephemeralPub: Data([1, 2]), ciphertext: Data([3, 4]))
        let vault = VaultFile(version: 1, seKey: Data([9]), sePub: Data([8]), tokens: [entry])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(VaultFile.self, from: enc.encode(vault))
        XCTAssertEqual(back.tokens, [entry])
        XCTAssertEqual(back.version, 1)
    }

    func testIsExpired() {
        var entry = TokenEntry(
            id: UUID(), label: "x", kind: .classic, permissions: [],
            expiresAt: nil, createdAt: Date(), lastActivatedAt: nil, notes: "",
            ephemeralPub: Data(), ciphertext: Data())
        XCTAssertFalse(entry.isExpired())
        entry.expiresAt = Date(timeIntervalSinceNow: -60)
        XCTAssertTrue(entry.isExpired())
        entry.expiresAt = Date(timeIntervalSinceNow: 60)
        XCTAssertFalse(entry.isExpired())
    }

    func testTokenEntryDecodesWithoutSummaryKey() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","label":"old","kind":"classic",
         "permissions":["repo"],"createdAt":"2026-07-07T12:00:00Z","notes":"",
         "ephemeralPub":"","ciphertext":""}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(TokenEntry.self, from: Data(json.utf8))
        XCTAssertNil(entry.summary)
        XCTAssertEqual(entry.menuSummary, "repo")
    }
}
