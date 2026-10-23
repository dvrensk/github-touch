import XCTest
@testable import GitHubTouchCore

final class VaultStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-test-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func makeVault() -> VaultFile {
        VaultFile(version: 1, seKey: Data([1]), sePub: Data([2]), tokens: [])
    }

    func testLoadReturnsNilWhenMissing() throws {
        XCTAssertNil(try VaultStore(directory: dir).load())
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = VaultStore(directory: dir)
        try store.save(makeVault())
        let back = try XCTUnwrap(store.load())
        XCTAssertEqual(back.seKey, Data([1]))
        XCTAssertEqual(back.sePub, Data([2]))
    }

    func testSaveSetsMode600() throws {
        let store = VaultStore(directory: dir)
        try store.save(makeVault())
        let attrs = try FileManager.default.attributesOfItem(atPath: store.vaultURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.int16Value, 0o600)
    }

    func testSaveOverwritesExistingVault() throws {
        let store = VaultStore(directory: dir)
        try store.save(makeVault())
        let second = VaultFile(version: 1, seKey: Data([7]), sePub: Data([2]), tokens: [])
        try store.save(second)
        let back = try XCTUnwrap(store.load())
        XCTAssertEqual(back.seKey, Data([7]))
        let attrs = try FileManager.default.attributesOfItem(atPath: store.vaultURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.int16Value, 0o600)
    }

    func testLoadThrowsOnCorruptFile() throws {
        let store = VaultStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.vaultURL)
        XCTAssertThrowsError(try store.load())
    }

    func testTagAndDefaultRoundTrip() throws {
        let store = VaultStore(directory: dir)
        let id = UUID()
        let entry = TokenEntry(id: id, label: "deploy", kind: .classic, permissions: [],
                               expiresAt: nil, createdAt: Date(timeIntervalSince1970: 0),
                               lastActivatedAt: nil, notes: "",
                               ephemeralPub: Data([3]), ciphertext: Data([4]), tag: .red)
        try store.save(VaultFile(version: 1, seKey: Data([1]), sePub: Data([2]),
                                 tokens: [entry], defaultTokenId: id))
        let back = try XCTUnwrap(store.load())
        XCTAssertEqual(back.tokens[0].tag, .red)
        XCTAssertEqual(back.defaultTokenId, id)
    }

    func testLegacyVaultWithoutTagOrDefaultDecodes() throws {
        let store = VaultStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        {"version":1,"seKey":"AQ==","sePub":"Ag==","tokens":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","label":"old","kind":"classic","permissions":[],"createdAt":"2026-07-07T10:00:00Z","notes":"","ephemeralPub":"Aw==","ciphertext":"BA=="}]}
        """
        try Data(json.utf8).write(to: store.vaultURL)
        let back = try XCTUnwrap(store.load())
        XCTAssertEqual(back.tokens[0].label, "old")
        XCTAssertNil(back.tokens[0].tag)
        XCTAssertNil(back.defaultTokenId)
    }
}
