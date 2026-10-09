import Foundation

/// Signing in to an NTS account. nts.live keeps its accounts in Firebase, which has a plain HTTP API.
public enum NtsAccount {
    public struct Tokens: Equatable, Sendable {
        /// Proves who is asking, and only lasts an hour.
        public let idToken: String
        /// Gets the next `idToken`, so this is what keeps someone signed in.
        public let refreshToken: String
        public let expires: Date

        public init(idToken: String, refreshToken: String, expires: Date) {
            self.idToken = idToken
            self.refreshToken = refreshToken
            self.expires = expires
        }
    }

    public enum Failure: Error, Equatable {
        case wrongCredentials
        case tooManyAttempts
        case disabled
        /// The refresh token no longer works, so signing in again is the only way on.
        case signedOut
        case unavailable
    }

    public static func signIn(email: String, password: String) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(apiKey)")!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Credentials(email: email, password: password))
        return try await send(request)
    }

    public static func refresh(_ refreshToken: String) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"), URLQueryItem(name: "refresh_token", value: refreshToken)]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        return try await send(request)
    }

    public static func parseTokens(_ body: Data, now: Date = .now) throws -> Tokens {
        guard let response = try? JSONDecoder().decode(Response.self, from: body) else { throw Failure.unavailable }
        if let message = response.error?.message { throw failure(for: message) }
        guard let idToken = response.idToken ?? response.id_token,
              let refreshToken = response.refreshToken ?? response.refresh_token,
              let lifetime = (response.expiresIn ?? response.expires_in).flatMap(TimeInterval.init) else {
            throw Failure.unavailable
        }
        return Tokens(idToken: idToken, refreshToken: refreshToken, expires: now.addingTimeInterval(lifetime))
    }

    /// The key nts.live itself ships to every browser. It names the project and is not a secret.
    private static let apiKey = "AIzaSyA4Qp5AvHC8Rev72-10-_DY614w_bxUCJU"

    private static func send(_ request: URLRequest) async throws -> Tokens {
        var request = request
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { throw Failure.unavailable }
        return try parseTokens(data)
    }

    private static func failure(for message: String) -> Failure {
        // Some codes come with a sentence after them: "TOO_MANY_ATTEMPTS_TRY_LATER : Access to this account…".
        let code = message.split(separator: " ").first.map(String.init) ?? message
        return switch code {
        case "INVALID_LOGIN_CREDENTIALS", "INVALID_PASSWORD", "EMAIL_NOT_FOUND", "INVALID_EMAIL", "MISSING_EMAIL", "MISSING_PASSWORD":
            .wrongCredentials
        case "TOO_MANY_ATTEMPTS_TRY_LATER":
            .tooManyAttempts
        case "USER_DISABLED":
            .disabled
        case "TOKEN_EXPIRED", "INVALID_REFRESH_TOKEN", "USER_NOT_FOUND", "MISSING_REFRESH_TOKEN":
            .signedOut
        default:
            .unavailable
        }
    }

    private struct Credentials: Encodable {
        let email: String
        let password: String
        let returnSecureToken = true
    }

    /// Signing in answers in camel case, refreshing in snake case.
    private struct Response: Decodable {
        let idToken: String?
        let refreshToken: String?
        let expiresIn: String?
        let id_token: String?
        let refresh_token: String?
        let expires_in: String?
        let error: ResponseError?
    }

    private struct ResponseError: Decodable {
        let message: String?
    }
}
