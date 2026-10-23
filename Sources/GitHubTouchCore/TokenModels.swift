import Foundation

public enum TokenKind: String, Codable, CaseIterable, Sendable {
    case fineGrained, classic, oauth

    public var displayName: String {
        switch self {
        case .fineGrained: return "Fine-grained PAT"
        case .classic: return "Classic PAT"
        case .oauth: return "OAuth token"
        }
    }
}

/// A user-chosen colour; the app never assigns or infers one.
public enum TokenTag: String, Codable, CaseIterable, Sendable {
    case green, orange, red
}

public struct TokenEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var kind: TokenKind
    public var permissions: [String]
    public var expiresAt: Date?
    public var createdAt: Date
    public var lastActivatedAt: Date?
    public var notes: String
    public var summary: String?
    public var ephemeralPub: Data
    public var ciphertext: Data
    public var tag: TokenTag?

    public init(id: UUID, label: String, kind: TokenKind, permissions: [String],
                expiresAt: Date?, createdAt: Date, lastActivatedAt: Date?, notes: String,
                summary: String? = nil, ephemeralPub: Data, ciphertext: Data,
                tag: TokenTag? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.permissions = permissions
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.lastActivatedAt = lastActivatedAt
        self.notes = notes
        self.summary = summary
        self.ephemeralPub = ephemeralPub
        self.ciphertext = ciphertext
        self.tag = tag
    }

    public func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    public var permissionSummary: String {
        permissions.isEmpty ? "no recorded permissions" : permissions.joined(separator: ", ")
    }

    /// What the menu row shows: the generated summary when present, else the
    /// raw permissions join.
    public var menuSummary: String {
        summary ?? permissionSummary
    }
}

public struct VaultFile: Codable, Sendable {
    public var version: Int
    public var seKey: Data   // Secure Enclave private key blob (usable only on this Mac)
    public var sePub: Data   // its x9.63 public key, for sealing without an SE round-trip
    public var tokens: [TokenEntry]
    public var defaultTokenId: UUID?

    public init(version: Int, seKey: Data, sePub: Data, tokens: [TokenEntry],
                defaultTokenId: UUID? = nil) {
        self.version = version
        self.seKey = seKey
        self.sePub = sePub
        self.tokens = tokens
        self.defaultTokenId = defaultTokenId
    }
}
