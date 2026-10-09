import Foundation
import NTSCore
import Observation

/// The NTS account that is signed in. The keychain holds what keeps it signed in; the password is never kept.
@MainActor
@Observable
final class Account {
    private(set) var email = UserDefaults.standard.string(forKey: emailKey)
    private(set) var isSigningIn = false
    /// Why signing in failed, or why the app signed out by itself.
    private(set) var problem: String?

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var tokens: NtsAccount.Tokens?
    @ObservationIgnored private var refreshing: Task<String?, Never>?
    // Tells an answer that comes back after signing out or in apart from a current one.
    @ObservationIgnored private var generation = 0

    private nonisolated static let emailKey = "accountEmail"
    private nonisolated static let tokenName = "refresh-token"
    // Keeps writes and deletes in the order they were asked for.
    private nonisolated static let keychain = DispatchQueue(label: "nl.sanderjanssen.nts.keychain")

    func signIn(email: String, password: String) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        problem = nil
        defer { isSigningIn = false }
        do {
            let tokens = try await NtsAccount.signIn(email: email, password: password)
            generation += 1
            refreshing = nil
            keep(tokens)
            self.email = email
            UserDefaults.standard.set(email, forKey: Self.emailKey)
            onChange?()
        } catch {
            problem = switch error as? NtsAccount.Failure {
            case .wrongCredentials: "That email and password do not match."
            case .tooManyAttempts: "Too many attempts. Try again later."
            case .disabled: "This account is disabled."
            default: "Could not reach NTS. Try again."
            }
        }
    }

    func signOut() {
        forget()
        problem = nil
        onChange?()
    }

    /// Nil when signed out, and when a new token could not be fetched just now.
    func idToken() async -> String? {
        guard email != nil else { return nil }
        if let tokens, tokens.expires.timeIntervalSinceNow > 60 { return tokens.idToken }
        // Callers share one refresh: the answer can carry a new refresh token that replaces the old one.
        let task = refreshing ?? Task { await refresh() }
        refreshing = task
        return await task.value
    }

    /// For a token the server turned down before its time.
    func discardIDToken() {
        guard let tokens else { return }
        self.tokens = NtsAccount.Tokens(idToken: tokens.idToken, refreshToken: tokens.refreshToken, expires: .distantPast)
    }

    private func refresh() async -> String? {
        let started = generation
        let known = tokens?.refreshToken
        do {
            let stored: String
            if let known {
                stored = known
            } else {
                switch await Self.storedToken() {
                case .value(let token): stored = token
                case .missing: throw NtsAccount.Failure.signedOut
                case .unreadable: throw NtsAccount.Failure.unavailable
                }
            }
            let fresh = try await NtsAccount.refresh(stored)
            guard generation == started else { return nil }
            refreshing = nil
            keep(fresh)
            return fresh.idToken
        } catch {
            guard generation == started else { return nil }
            refreshing = nil
            if error as? NtsAccount.Failure == .signedOut {
                forget()
                problem = "You were signed out. Sign in again."
                onChange?()
            }
            return nil
        }
    }

    private func keep(_ fresh: NtsAccount.Tokens) {
        if fresh.refreshToken != tokens?.refreshToken {
            Self.keychain.async { Keychain.write(fresh.refreshToken, as: Self.tokenName) }
        }
        tokens = fresh
    }

    private func forget() {
        generation += 1
        refreshing = nil
        tokens = nil
        email = nil
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
        Self.keychain.async { Keychain.delete(Self.tokenName) }
    }

    private nonisolated static func storedToken() async -> Keychain.Answer {
        await withCheckedContinuation { continuation in
            keychain.async { continuation.resume(returning: Keychain.read(tokenName)) }
        }
    }
}
