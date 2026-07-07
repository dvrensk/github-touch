import Foundation

/// Turns what we know about a token (scopes or probe results) into the menu
/// one-liner and the capability details list. Pure — no I/O. This is the seam
/// where an LLM could plug in later; deliberately not done (spec).
public enum DescriptionBuilder {
    public static func build(kind: TokenKind, scopes: [String]?, probe: ProbeReport?,
                             expiresAt: Date?) -> (summary: String, details: [String]) {
        var summary = ""
        var details: [String] = []

        if let scopes, !scopes.isEmpty {
            let described = scopes.map { scope -> String in
                let (phrase, dangerous) = ScopeCatalog.describe(scope)
                return dangerous ? "⚠ \(phrase)" : phrase
            }
            summary = truncate(described.joined(separator: ", "), to: 60)
            details = described
        } else if let probe {
            var parts: [String] = []
            if case .granted(let names) = probe.repos {
                let names = names ?? []
                if names.isEmpty {
                    parts.append("repos")
                } else {
                    let shown = names.prefix(2).joined(separator: ", ")
                    let more = names.count > 2 ? " (+\(names.count - 2))" : ""
                    parts.append("repos: \(shown)\(more)")
                }
            }
            if case .granted = probe.orgs { parts.append("orgs") }
            if case .granted = probe.gists { parts.append("gists") }
            if case .granted = probe.notifications { parts.append("notifications") }
            if case .granted = probe.emails { parts.append("email") }
            summary = parts.isEmpty ? "no API read access found"
                                    : truncate(parts.joined(separator: "; "), to: 60)
            details = [
                detailLine(probe.repos, granted: { names in
                    "repo access: " + ((names?.isEmpty ?? true) ? "none visible" : names!.joined(separator: ", "))
                }, deniedName: "repo", unknownName: "repo"),
                detailLine(probe.orgs, granted: { _ in "org read access" },
                           deniedName: "org", unknownName: "org"),
                detailLine(probe.gists, granted: { _ in "gist read access" },
                           deniedName: "gist", unknownName: "gist"),
                detailLine(probe.notifications, granted: { _ in "notifications read access" },
                           deniedName: "notifications", unknownName: "notifications"),
                detailLine(probe.emails, granted: { _ in "email read access" },
                           deniedName: "email", unknownName: "email"),
            ]
        }

        if let expiresAt {
            details.append("expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
        }
        return (summary, details)
    }

    private static func detailLine(_ outcome: ProbeOutcome,
                                   granted: ([String]?) -> String,
                                   deniedName: String, unknownName: String) -> String {
        switch outcome {
        case .granted(let detail):
            return granted(detail)
        case .denied(let needed):
            let suffix = needed.map { " (needs: \($0))" } ?? ""
            return "no \(deniedName) access\(suffix)"
        case .unknown:
            return "\(unknownName) access: probe failed"
        }
    }

    static func truncate(_ s: String, to limit: Int) -> String {
        guard s.count > limit else { return s }
        var head = String(s.prefix(limit))
        if let lastSpace = head.lastIndex(of: " ") {
            head = String(head[..<lastSpace])
        }
        while head.hasSuffix(",") || head.hasSuffix(";") { head.removeLast() }
        return head + "…"
    }
}
