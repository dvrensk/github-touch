import XCTest
@testable import GitHubTouchCore

final class ActivationStateTests: XCTestCase {
    func testNextMidnightIsStartOfNextDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-07-07T15:30:00+02:00")!
        let midnight = nextMidnight(after: now, calendar: calendar)
        XCTAssertEqual(midnight, formatter.date(from: "2026-07-08T00:00:00+02:00"))
    }

    func testNextMidnightJustBeforeMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-07-07T23:59:59+02:00")!
        XCTAssertEqual(nextMidnight(after: now, calendar: calendar),
                       formatter.date(from: "2026-07-08T00:00:00+02:00"))
    }

    func testIsOverdue() {
        let state = ActivationState(activeTokenId: UUID(), clearAt: Date(timeIntervalSinceNow: -1))
        XCTAssertTrue(state.isOverdue())
        let future = ActivationState(activeTokenId: UUID(), clearAt: Date(timeIntervalSinceNow: 60))
        XCTAssertFalse(future.isOverdue())
        XCTAssertFalse(ActivationState().isOverdue())
        XCTAssertFalse(ActivationState().isActive)
    }

    func testStoreRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "github-touch-tests"))
        defaults.removePersistentDomain(forName: "github-touch-tests")
        let store = ActivationStateStore(defaults: defaults)

        XCTAssertEqual(store.load(), ActivationState())

        let state = ActivationState(activeTokenId: UUID(), clearAt: Date(timeIntervalSince1970: 1_790_000_000))
        store.save(state)
        XCTAssertEqual(store.load(), state)

        store.save(ActivationState())
        XCTAssertEqual(store.load(), ActivationState())
        defaults.removePersistentDomain(forName: "github-touch-tests")
    }
}
