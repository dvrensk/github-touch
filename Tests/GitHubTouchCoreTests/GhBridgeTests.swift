import XCTest
@testable import GitHubTouchCore

final class GhBridgeTests: XCTestCase {
    var dir: URL!
    var ghPath: String { dir.appendingPathComponent("gh").path }
    var bridge: GhBridge { GhBridge(ghPath: ghPath) }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gh-fake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Fake gh: `auth login` records stdin and marks logged-in via a state
        // file; `auth status` reports it; `auth logout` clears it.
        let script = """
        #!/bin/bash
        D="$(cd "$(dirname "$0")" && pwd)"
        echo "$*" >> "$D/log"
        case "$1 $2" in
          "auth status") [ -f "$D/state" ] && exit 0 || exit 1 ;;
          "auth login")  cat > "$D/stdin.txt"; touch "$D/state"; exit 0 ;;
          "auth logout") rm -f "$D/state"; exit 0 ;;
          "auth token")  [ -f "$D/state" ] && { echo "gho_fake123"; exit 0; } || exit 1 ;;
        esac
        exit 64
        """
        try script.write(toFile: ghPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ghPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testActivateSendsTokenViaStdinNeverArgv() throws {
        try bridge.activate(token: "ghp_supersecret")
        let stdin = try String(contentsOf: dir.appendingPathComponent("stdin.txt"), encoding: .utf8)
        XCTAssertEqual(stdin, "ghp_supersecret")
        let log = try String(contentsOf: dir.appendingPathComponent("log"), encoding: .utf8)
        XCTAssertFalse(log.contains("supersecret"), "token must never appear on argv")
        XCTAssertTrue(log.contains("auth login --hostname github.com --with-token"))
    }

    func testIsLoggedInReflectsGhState() throws {
        XCTAssertFalse(bridge.isLoggedIn())
        try bridge.activate(token: "t")
        XCTAssertTrue(bridge.isLoggedIn())
    }

    func testDeactivateLogsOutAndIsIdempotent() throws {
        try bridge.activate(token: "t")
        try bridge.deactivate()
        XCTAssertFalse(bridge.isLoggedIn())
        try bridge.deactivate() // already logged out: must not throw
    }

    func testCurrentToken() throws {
        XCTAssertNil(bridge.currentToken())
        try bridge.activate(token: "t")
        XCTAssertEqual(bridge.currentToken(), "gho_fake123")
    }

    func testDiscoverReturnsNilWhenAbsent() {
        XCTAssertNil(GhBridge.discover(extraPaths: ["/nonexistent/gh"]))
    }

    func testDiscoverFindsExecutable() {
        XCTAssertEqual(GhBridge.discover(extraPaths: [ghPath])?.ghPath, ghPath)
    }
}
