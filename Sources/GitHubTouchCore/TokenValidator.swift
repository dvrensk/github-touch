import Foundation

public struct TokenInfo: Equatable, Sendable {
    public var login: String
    public var scopes: [String]?   // nil for fine-grained tokens (no scope header)
    public var expiresAt: Date?
}

public enum TokenValidationError: Error, Equatable {
    case invalidToken
    case unexpectedStatus(Int)
}

extension TokenValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "GitHub rejected the token (401)."
        case .unexpectedStatus(let code):
            return "GitHub returned an unexpected HTTP \(code)."
        }
    }
}

public struct TokenValidator {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func validate(_ token: String) async throws -> TokenInfo {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        guard http.statusCode == 200 else {
            throw http.statusCode == 401
                ? TokenValidationError.invalidToken
                : TokenValidationError.unexpectedStatus(http.statusCode)
        }
        struct User: Decodable { let login: String }
        let user = try JSONDecoder().decode(User.self, from: data)
        let scopes = http.value(forHTTPHeaderField: "X-OAuth-Scopes").map {
            $0.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let expiry = http.value(forHTTPHeaderField: "GitHub-Authentication-Token-Expiration")
            .flatMap(Self.parseExpiration)
        return TokenInfo(login: user.login,
                         scopes: (scopes?.isEmpty ?? true) ? nil : scopes,
                         expiresAt: expiry)
    }

    /// GitHub sends "2026-10-01 07:00:00 UTC"; be lenient and take ISO8601 too.
    static func parseExpiration(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        if let date = formatter.date(from: string) { return date }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        if let date = formatter.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
