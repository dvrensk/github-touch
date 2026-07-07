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

    func testLoadThrowsOnCorruptFile() throws {
        let store = VaultStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.vaultURL)
        XCTAssertThrowsError(try store.load())
    }
}
