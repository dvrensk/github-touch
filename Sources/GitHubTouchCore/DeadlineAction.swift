import Foundation

public enum LogoutReason: Equatable, Sendable {
    case noDefault, defaultNotHeld, defaultChanged, defaultExpired
}

public enum DeadlineAction: Equatable, Sendable {
    case switchToDefault(UUID)
    case logout(LogoutReason)
}

/// What to do when a timed activation runs out. Switching back needs the
/// default's secret already in memory — it must never prompt for Touch ID —
/// and only for the token that is still the default.
public func deadlineAction(defaultTokenId: UUID?, heldDefaultId: UUID?,
                           defaultExpired: Bool) -> DeadlineAction {
    guard let defaultTokenId else { return .logout(.noDefault) }
    // An expired default is never unsealed, so check expiry before holding.
    guard !defaultExpired else { return .logout(.defaultExpired) }
    guard let heldDefaultId else { return .logout(.defaultNotHeld) }
    guard heldDefaultId == defaultTokenId else { return .logout(.defaultChanged) }
    return .switchToDefault(defaultTokenId)
}
