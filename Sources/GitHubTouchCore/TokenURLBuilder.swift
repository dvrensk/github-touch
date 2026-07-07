import Foundation

public enum TokenURLBuilder {
    public static let fineGrainedNewTokenURL =
        URL(string: "https://github.com/settings/personal-access-tokens/new")!

    /// github.com pre-fills the classic-token form from these query params.
    public static func classicNewTokenURL(scopes: [String], description: String) -> URL {
        var components = URLComponents(string: "https://github.com/settings/tokens/new")!
        components.queryItems = [
            URLQueryItem(name: "scopes", value: scopes.joined(separator: ",")),
            URLQueryItem(name: "description", value: description),
        ]
        return components.url!
    }

    public static let classicScopeChoices: [(scope: String, help: String)] = [
        ("repo", "full read/write on ALL repos"),
        ("public_repo", "read/write on public repos only"),
        ("gist", "create and edit gists"),
        ("workflow", "update GitHub Actions workflows"),
        ("read:org", "read org membership"),
        ("admin:org", "manage org settings"),
        ("notifications", "read notifications"),
        ("delete_repo", "delete repositories"),
    ]
}
