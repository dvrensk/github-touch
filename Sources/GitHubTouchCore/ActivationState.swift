import Foundation

/// How long a non-default activation lasts.
public enum ActivationDuration: String, CaseIterable, Codable, Sendable {
    case fifteenMinutes, thirtyMinutes, oneHour, untilMidnight

    public var menuTitle: String {
        switch self {
        case .fifteenMinutes: return "15 min"
        case .thirtyMinutes: return "30 min"
        case .oneHour: return "1 hour"
        case .untilMidnight: return "Until midnight"
        }
    }

    public var minutes: Int? {
        switch self {
        case .fifteenMinutes: return 15
        case .thirtyMinutes: return 30
        case .oneHour: return 60
        case .untilMidnight: return nil
        }
    }

    public func clearAt(from now: Date, calendar: Calendar = .current) -> Date {
        guard let minutes else { return nextMidnight(after: now, calendar: calendar) }
        return now.addingTimeInterval(TimeInterval(minutes * 60))
    }
}

/// `clearAt == nil` with an active token means no timer (the default token).
public struct ActivationState: Equatable, Sendable {
    public var activeTokenId: UUID?
    public var clearAt: Date?
    public var untilMidnight: Bool

    public init(activeTokenId: UUID? = nil, clearAt: Date? = nil, untilMidnight: Bool = false) {
        self.activeTokenId = activeTokenId
        self.clearAt = clearAt
        self.untilMidnight = untilMidnight
    }

    public var isActive: Bool { activeTokenId != nil }

    public func isOverdue(now: Date = Date()) -> Bool {
        guard let clearAt else { return false }
        return now >= clearAt
    }

    /// Pushes the deadline forward from the current deadline, not from now.
    /// "Until midnight" means tonight's midnight, and never shortens a
    /// timer that already runs past it.
    public func extended(by duration: ActivationDuration, now: Date = Date(),
                         calendar: Calendar = .current) -> ActivationState {
        guard let clearAt else { return self }
        var next = self
        if let minutes = duration.minutes {
            next.clearAt = clearAt.addingTimeInterval(TimeInterval(minutes * 60))
            next.untilMidnight = false
        } else {
            next.clearAt = max(clearAt, nextMidnight(after: now, calendar: calendar))
            next.untilMidnight = true
        }
        return next
    }

    /// The default token runs without a timer; any other active token needs
    /// one, so an ex-default falls back to the midnight rule.
    public func reconciled(withDefault defaultId: UUID?, now: Date = Date(),
                           calendar: Calendar = .current) -> ActivationState {
        guard let activeTokenId else { return self }
        var next = self
        if activeTokenId == defaultId {
            next.clearAt = nil
            next.untilMidnight = false
        } else if clearAt == nil {
            next.clearAt = nextMidnight(after: now, calendar: calendar)
            next.untilMidnight = true
        }
        return next
    }

    /// Minutes left for a finite timer, as shown beside the menu bar icon.
    public func countdownText(now: Date = Date()) -> String? {
        guard isActive, let clearAt, !untilMidnight else { return nil }
        let remaining = clearAt.timeIntervalSince(now)
        if remaining >= 60 { return "\(Int((remaining / 60).rounded(.up)))m" }
        return remaining > 0 ? "<1m" : nil
    }
}

public func nextMidnight(after date: Date = Date(), calendar: Calendar = .current) -> Date {
    calendar.nextDate(after: date,
                      matching: DateComponents(hour: 0, minute: 0, second: 0),
                      matchingPolicy: .nextTime)!
}

public final class ActivationStateStore {
    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ActivationState {
        ActivationState(
            activeTokenId: defaults.string(forKey: "activeTokenId").flatMap(UUID.init(uuidString:)),
            clearAt: defaults.object(forKey: "clearAt") as? Date,
            // Builds before durations always timed out at midnight and saved no flag.
            untilMidnight: defaults.object(forKey: "untilMidnight") == nil
                ? defaults.object(forKey: "clearAt") != nil
                : defaults.bool(forKey: "untilMidnight"))
    }

    public func save(_ state: ActivationState) {
        if let id = state.activeTokenId {
            defaults.set(id.uuidString, forKey: "activeTokenId")
        } else {
            defaults.removeObject(forKey: "activeTokenId")
        }
        if let clearAt = state.clearAt {
            defaults.set(clearAt, forKey: "clearAt")
        } else {
            defaults.removeObject(forKey: "clearAt")
        }
        defaults.set(state.untilMidnight, forKey: "untilMidnight")
    }

    public func loadDuration() -> ActivationDuration {
        defaults.string(forKey: "activationDuration").flatMap(ActivationDuration.init(rawValue:))
            ?? .untilMidnight
    }

    public func saveDuration(_ duration: ActivationDuration) {
        defaults.set(duration.rawValue, forKey: "activationDuration")
    }
}
