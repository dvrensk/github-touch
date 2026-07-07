import Foundation

public struct ActivationState: Equatable, Sendable {
    public var activeTokenId: UUID?
    public var clearAt: Date?

    public init(activeTokenId: UUID? = nil, clearAt: Date? = nil) {
        self.activeTokenId = activeTokenId
        self.clearAt = clearAt
    }

    public var isActive: Bool { activeTokenId != nil }

    public func isOverdue(now: Date = Date()) -> Bool {
        guard let clearAt else { return false }
        return now >= clearAt
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
            clearAt: defaults.object(forKey: "clearAt") as? Date)
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
    }
}
