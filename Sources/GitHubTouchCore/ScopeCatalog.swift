import Foundation

/// Plain-English phrases for classic/OAuth token scopes, per the spec's table.
public enum ScopeCatalog {
    static let table: [String: (phrase: String, dangerous: Bool)] = [
        "repo": ("read/write ALL repos", true),
        "public_repo": ("read/write public repos", false),
        "delete_repo": ("delete repos", true),
        "admin:org": ("manage org", true),
        "write:org": ("write org data", true),
        "read:org": ("read org membership", false),
        "gist": ("gists", false),
        "workflow": ("edit Actions workflows", true),
        "notifications": ("notifications", false),
        "user": ("read profile", false),
        "read:user": ("read profile", false),
        "user:email": ("read email", false),
    ]

    public static func describe(_ scope: String) -> (phrase: String, dangerous: Bool) {
        table[scope] ?? (scope, false)
    }
}
