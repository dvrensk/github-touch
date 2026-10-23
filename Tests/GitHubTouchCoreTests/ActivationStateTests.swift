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

    // MARK: - Durations, extend, reconcile, countdown

    private var madrid: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private var t0: Date { date("2026-07-07T15:30:00+02:00") }

    func testDurationClearAt() {
        XCTAssertEqual(ActivationDuration.fifteenMinutes.clearAt(from: t0, calendar: madrid),
                       t0.addingTimeInterval(900))
        XCTAssertEqual(ActivationDuration.oneHour.clearAt(from: t0, calendar: madrid),
                       t0.addingTimeInterval(3600))
        XCTAssertEqual(ActivationDuration.untilMidnight.clearAt(from: t0, calendar: madrid),
                       date("2026-07-08T00:00:00+02:00"))
    }

    func testDurationMenuTitlesInOrder() {
        XCTAssertEqual(ActivationDuration.allCases.map(\.menuTitle),
                       ["15 min", "30 min", "1 hour", "Until midnight"])
    }

    func testExtendedAddsFromClearAtNotNow() {
        let state = ActivationState(activeTokenId: UUID(), clearAt: t0.addingTimeInterval(600))
        let twice = state.extended(by: .fifteenMinutes, calendar: madrid)
            .extended(by: .fifteenMinutes, calendar: madrid)
        XCTAssertEqual(twice.clearAt, t0.addingTimeInterval(600 + 1800))
        XCTAssertFalse(twice.untilMidnight)
    }

    func testExtendedUntilMidnightSetsFlag() {
        let state = ActivationState(activeTokenId: UUID(), clearAt: t0.addingTimeInterval(600))
        let extended = state.extended(by: .untilMidnight, now: t0, calendar: madrid)
        XCTAssertEqual(extended.clearAt, date("2026-07-08T00:00:00+02:00"))
        XCTAssertTrue(extended.untilMidnight)
    }

    func testExtendedNoOpWithoutClearAt() {
        let state = ActivationState(activeTokenId: UUID())
        XCTAssertEqual(state.extended(by: .thirtyMinutes, calendar: madrid), state)
    }

    func testReconciledMakesNewDefaultTimerless() {
        let id = UUID()
        let state = ActivationState(activeTokenId: id, clearAt: t0.addingTimeInterval(600),
                                    untilMidnight: true)
        let reconciled = state.reconciled(withDefault: id, now: t0, calendar: madrid)
        XCTAssertNil(reconciled.clearAt)
        XCTAssertFalse(reconciled.untilMidnight)
        XCTAssertEqual(reconciled.activeTokenId, id)
    }

    func testReconciledGivesExDefaultAMidnightTimer() {
        let id = UUID()
        let state = ActivationState(activeTokenId: id)
        for newDefault in [nil, UUID()] {
            let reconciled = state.reconciled(withDefault: newDefault, now: t0, calendar: madrid)
            XCTAssertEqual(reconciled.clearAt, date("2026-07-08T00:00:00+02:00"))
            XCTAssertTrue(reconciled.untilMidnight)
        }
    }

    func testReconciledLeavesTimedNonDefaultAlone() {
        let state = ActivationState(activeTokenId: UUID(), clearAt: t0.addingTimeInterval(600))
        XCTAssertEqual(state.reconciled(withDefault: UUID(), now: t0, calendar: madrid), state)
        XCTAssertEqual(ActivationState().reconciled(withDefault: UUID(), now: t0, calendar: madrid),
                       ActivationState())
    }

    func testCountdownText() {
        let id = UUID()
        func text(_ offset: TimeInterval, untilMidnight: Bool = false) -> String? {
            ActivationState(activeTokenId: id, clearAt: t0.addingTimeInterval(offset),
                            untilMidnight: untilMidnight).countdownText(now: t0)
        }
        XCTAssertEqual(text(23 * 60 + 10), "24m")
        XCTAssertEqual(text(30), "<1m")
        XCTAssertNil(text(-1))
        XCTAssertNil(text(600, untilMidnight: true))
        XCTAssertNil(ActivationState(activeTokenId: id).countdownText(now: t0))
    }

    func testStoreRoundTripsUntilMidnightAndDuration() throws {
        let suite = "github-touch-tests-duration"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ActivationStateStore(defaults: defaults)

        let state = ActivationState(activeTokenId: UUID(),
                                    clearAt: Date(timeIntervalSince1970: 1_790_000_000),
                                    untilMidnight: true)
        store.save(state)
        XCTAssertEqual(store.load(), state)

        XCTAssertEqual(store.loadDuration(), .untilMidnight)
        store.saveDuration(.thirtyMinutes)
        XCTAssertEqual(store.loadDuration(), .thirtyMinutes)
    }

    func testExtendedUntilMidnightAfterCrossingMidnightStaysTonight() {
        // 23:50 with 15 min left → clearAt 00:05; "until midnight" must not
        // jump to the following night.
        let now = date("2026-07-07T23:50:00+02:00")
        let state = ActivationState(activeTokenId: UUID(), clearAt: date("2026-07-08T00:05:00+02:00"))
        let extended = state.extended(by: .untilMidnight, now: now, calendar: madrid)
        XCTAssertEqual(extended.clearAt, date("2026-07-08T00:05:00+02:00"))
    }

    func testExtendedByMinutesClearsUntilMidnight() {
        let midnight = date("2026-07-08T00:00:00+02:00")
        let state = ActivationState(activeTokenId: UUID(), clearAt: midnight, untilMidnight: true)
        let extended = state.extended(by: .thirtyMinutes, now: t0, calendar: madrid)
        XCTAssertEqual(extended.clearAt, midnight.addingTimeInterval(1800))
        XCTAssertFalse(extended.untilMidnight)
    }

    func testStoreTreatsLegacyTimedActivationAsUntilMidnight() throws {
        let suite = "github-touch-tests-legacy"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        // what a pre-duration build saved: an id and a midnight clearAt, no flag
        defaults.set(UUID().uuidString, forKey: "activeTokenId")
        defaults.set(Date(timeIntervalSince1970: 1_790_000_000), forKey: "clearAt")
        XCTAssertTrue(ActivationStateStore(defaults: defaults).load().untilMidnight)

        defaults.removeObject(forKey: "clearAt")
        XCTAssertFalse(ActivationStateStore(defaults: defaults).load().untilMidnight)
    }
}

final class ActivationDurationPhraseTests: XCTestCase {
    func testActivationPhrase() {
        XCTAssertEqual(ActivationDuration.allCases.map(\.activationPhrase),
                       ["Activate for 15 min", "Activate for 30 min", "Activate for 1 hour",
                        "Activate until midnight"])
    }
}
