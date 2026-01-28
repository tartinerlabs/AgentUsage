//
//  TokenRefreshService.swift
//  ClaudeMeter
//
//  Service for refreshing expired OAuth tokens
//

import Foundation

/// Service for refreshing expired OAuth tokens using refresh_token
actor TokenRefreshService {
    static let shared = TokenRefreshService()

    private let tokenURL = URL(string: "https://api.anthropic.com/oauth/token")!

    private init() {}

    /// Attempt to refresh expired credentials using the refresh token
    /// - Parameter credentials: Current (possibly expired) credentials
    /// - Returns: New credentials with fresh access token
    /// - Throws: TokenRefreshError if refresh fails
    func refreshIfNeeded(_ credentials: ClaudeOAuthCredentials) async throws -> ClaudeOAuthCredentials {
        // Check if token is expired or about to expire (within 5 minutes)
        guard credentials.isExpired || credentials.isAboutToExpire else {
            return credentials
        }

        // Ensure we have a refresh token
        guard let refreshToken = credentials.refreshToken else {
            throw TokenRefreshError.noRefreshToken
        }

        return try await performRefresh(refreshToken: refreshToken)
    }

    private func performRefresh(refreshToken: String) async throws -> ClaudeOAuthCredentials {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TokenRefreshError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenRefreshError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseTokenResponse(data)
        case 400, 401:
            throw TokenRefreshError.invalidRefreshToken
        default:
            throw TokenRefreshError.serverError(httpResponse.statusCode)
        }
    }

    private func parseTokenResponse(_ data: Data) throws -> ClaudeOAuthCredentials {
        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: Int?
            let tokenType: String?
            let scope: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
                case tokenType = "token_type"
                case scope
            }
        }

        let response = try JSONDecoder().decode(TokenResponse.self, from: data)

        // Calculate expiration time (expires_in is in seconds)
        let expiresAtMs: Double?
        if let expiresIn = response.expiresIn {
            expiresAtMs = (Date().timeIntervalSince1970 + Double(expiresIn)) * 1000
        } else {
            expiresAtMs = nil
        }

        // Parse scopes
        let scopes = response.scope?.components(separatedBy: " ") ?? []

        return ClaudeOAuthCredentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: expiresAtMs,
            scopes: scopes,
            subscriptionType: nil,
            rateLimitTier: nil
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
    /// Check if token is about to expire (within 5 minutes)
    var isAboutToExpire: Bool {
        guard let expiresAt else { return false }
        let expiresDate = Date(timeIntervalSince1970: expiresAt / 1000)
        let bufferSeconds: TimeInterval = 300 // 5 minutes
        return Date().addingTimeInterval(bufferSeconds) >= expiresDate
    }
}
