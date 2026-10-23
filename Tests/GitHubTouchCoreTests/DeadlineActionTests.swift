import XCTest
@testable import GitHubTouchCore

final class DeadlineActionTests: XCTestCase {
    let defaultId = UUID()

    func testDeadlineActionNoDefault() {
        XCTAssertEqual(deadlineAction(defaultTokenId: nil, heldDefaultId: nil, defaultExpired: false),
                       .logout(.noDefault))
    }

    func testDeadlineActionNoDefaultWinsOverHeld() {
        XCTAssertEqual(deadlineAction(defaultTokenId: nil, heldDefaultId: UUID(), defaultExpired: false),
                       .logout(.noDefault))
    }

    func testDeadlineActionNotHeld() {
        XCTAssertEqual(deadlineAction(defaultTokenId: defaultId, heldDefaultId: nil, defaultExpired: false),
                       .logout(.defaultNotHeld))
    }

    func testDeadlineActionChanged() {
        XCTAssertEqual(deadlineAction(defaultTokenId: defaultId, heldDefaultId: UUID(), defaultExpired: false),
                       .logout(.defaultChanged))
    }

    func testDeadlineActionExpired() {
        XCTAssertEqual(deadlineAction(defaultTokenId: defaultId, heldDefaultId: defaultId, defaultExpired: true),
                       .logout(.defaultExpired))
    }

    func testDeadlineActionSwitchesToDefault() {
        XCTAssertEqual(deadlineAction(defaultTokenId: defaultId, heldDefaultId: defaultId, defaultExpired: false),
                       .switchToDefault(defaultId))
    }
}
