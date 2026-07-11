//
//  TokenRefreshService.swift
//  AgentUsage
//
//  Refreshes an expired Claude OAuth access token using the refresh token.
//

import Foundation

/// Refreshes Claude OAuth tokens against Anthropic's token endpoint, mirroring
/// Claude Code's own flow (endpoint + client_id + scope from `Constants`).
///
/// This only fetches new tokens; persisting them (and the keychain write-back that
/// keeps Claude Code working, since refresh tokens rotate) is the caller's job — see
/// `MacOSCredentialService`. Gated behind the opt-in `autoRefreshClaudeTokenKey`.
actor TokenRefreshService {
    static let shared = TokenRefreshService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// New tokens returned by a successful refresh.
    struct RefreshedTokens: Sendable {
        let accessToken: String
        /// Anthropic rotates refresh tokens, so a fresh one usually accompanies each refresh.
        let refreshToken: String?
        let expiresInSeconds: Int?
        let scopes: [String]?
    }

    /// Exchanges a refresh token for a new access token.
    /// - Throws: `TokenRefreshError` on network/HTTP failure or an invalid refresh token.
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        var request = URLRequest(url: Constants.claudeOAuthTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Constants.requestTimeout

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Constants.claudeOAuthClientID,
            "scope": Constants.claudeOAuthScope
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TokenRefreshError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TokenRefreshError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            return try parse(data)
        case 400, 401:
            // invalid_grant — the refresh token itself is expired/revoked/rotated away.
            throw TokenRefreshError.invalidRefreshToken
        default:
            throw TokenRefreshError.serverError(http.statusCode)
        }
    }

    private func parse(_ data: Data) throws -> RefreshedTokens {
        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: Int?
            let scope: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
                case scope
            }
        }

        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw TokenRefreshError.invalidResponse
        }

        let scopes = response.scope?
            .split(separator: " ")
            .map(String.init)

        return RefreshedTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresInSeconds: response.expiresIn,
            scopes: (scopes?.isEmpty ?? true) ? nil : scopes
        )
    }
}

/// Errors that can occur during token refresh
enum TokenRefreshError: LocalizedError {
    case noRefreshToken
    case networkError(Error)
    case invalidResponse
    case invalidRefreshToken
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No refresh token available. Please re-authenticate with Claude CLI."
        case .networkError(let error):
            return "Network error during token refresh: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response during token refresh."
        case .invalidRefreshToken:
            return "Refresh token is invalid or expired. Please re-authenticate with Claude CLI."
        case .serverError(let code):
            return "Server error during token refresh: \(code)"
        }
    }
}

// MARK: - ClaudeOAuthCredentials Extensions

extension ClaudeOAuthCredentials {
    /// Whether the token is within 5 minutes of expiring (refresh proactively).
    var isAboutToExpire: Bool {
        guard let expiresAtDate else { return false }
        let bufferSeconds: TimeInterval = 300 // 5 minutes
        return Date().addingTimeInterval(bufferSeconds) >= expiresAtDate
    }
}
