import Foundation

public enum ProbeOutcome: Equatable, Sendable {
    case granted(detail: [String]?)  // repo names for the repos probe, nil elsewhere
    case denied(needed: String?)     // X-Accepted-GitHub-Permissions header when present
    case unknown                     // network error, timeout, or unexpected status
}

public struct ProbeReport: Equatable, Sendable {
    public var repos: ProbeOutcome
    public var orgs: ProbeOutcome
    public var gists: ProbeOutcome
    public var notifications: ProbeOutcome
    public var emails: ProbeOutcome

    public init(repos: ProbeOutcome = .unknown, orgs: ProbeOutcome = .unknown,
                gists: ProbeOutcome = .unknown, notifications: ProbeOutcome = .unknown,
                emails: ProbeOutcome = .unknown) {
        self.repos = repos
        self.orgs = orgs
        self.gists = gists
        self.notifications = notifications
        self.emails = emails
    }
}

/// Discovers what a fine-grained token can read by trying cheap, read-only
/// endpoints. Write access is never probed (probing would mutate).
public struct CapabilityProber {
    let session: URLSession

    public init(session: URLSession = ephemeralAPISession) {
        self.session = session
    }

    enum Endpoint: String, CaseIterable {
        case repos = "/user/repos?per_page=100"
        case orgs = "/user/orgs"
        case gists = "/gists"
        case notifications = "/notifications"
        case emails = "/user/emails"
    }

    public func probe(_ token: String) async throws -> ProbeReport {
        var outcomes: [Endpoint: ProbeOutcome] = [:]
        try await withThrowingTaskGroup(of: (Endpoint, ProbeOutcome).self) { group in
            for endpoint in Endpoint.allCases {
                group.addTask { (endpoint, try await probeOne(endpoint, token: token)) }
            }
            do {
                for try await (endpoint, outcome) in group {
                    outcomes[endpoint] = outcome
                }
            } catch {
                group.cancelAll()
                throw error
            }
        }
        return ProbeReport(repos: outcomes[.repos] ?? .unknown,
                           orgs: outcomes[.orgs] ?? .unknown,
                           gists: outcomes[.gists] ?? .unknown,
                           notifications: outcomes[.notifications] ?? .unknown,
                           emails: outcomes[.emails] ?? .unknown)
    }

    private func probeOne(_ endpoint: Endpoint, token: String) async throws -> ProbeOutcome {
        var request = URLRequest(url: URL(string: "https://api.github.com" + endpoint.rawValue)!)
        request.timeoutInterval = 5
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .unknown
        }
        guard let http = response as? HTTPURLResponse else { return .unknown }
        switch http.statusCode {
        case 200:
            guard endpoint == .repos else { return .granted(detail: nil) }
            struct Repo: Decodable { let name: String }
            let names = (try? JSONDecoder().decode([Repo].self, from: data))?.map(\.name) ?? []
            return .granted(detail: names)
        case 401:
            throw TokenValidationError.invalidToken
        case 403, 404:
            // fine-grained tokens get 403 (or 404 on some endpoints) when the
            // permission is missing
            return .denied(needed: http.value(forHTTPHeaderField: "X-Accepted-GitHub-Permissions"))
        default:
            return .unknown
        }
    }
}
