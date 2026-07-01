//
//  BlogOAuthService.swift
//  ClaudeMeter
//
//  OAuth 2.1 / PKCE sign-in against the blog (Better Auth) OAuth provider.
//

#if os(macOS)
import AuthenticationServices
import CryptoKit
import Foundation
import OSLog

// MARK: - Token model

/// Persisted OAuth token blob for the blog provider. Stored as a single JSON entry in
/// the login Keychain (via the `/usr/bin/security` CLI, like `BlogUsageSyncService`).
nonisolated struct BlogOAuthTokens: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String?
    /// Absolute expiry in milliseconds since epoch (matches `ClaudeOAuthCredentials`).
    var expiresAt: Double?
    var scope: String?
    /// Dynamically-registered public client_id this token belongs to.
    var clientID: String
    /// Best-effort account email from userinfo, for the settings display.
    var accountEmail: String?

    /// True once the access token is past its expiry.
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date().timeIntervalSince1970 * 1000 >= expiresAt
    }

    /// True when the token expires within the next 5 minutes (refresh buffer).
    var isAboutToExpire: Bool {
        guard let expiresAt else { return false }
        let expiresDate = Date(timeIntervalSince1970: expiresAt / 1000)
        return Date().addingTimeInterval(300) >= expiresDate
    }
}

// MARK: - Provider abstraction (for sync-service injection / testing)

nonisolated protocol BlogAccessTokenProviding: Sendable {
    /// A currently-valid access token, refreshing if needed. `nil` when not signed in.
    func validAccessToken() async throws -> String?
}

// MARK: - Errors

enum BlogOAuthError: LocalizedError, Sendable {
    case discoveryFailed
    case registrationFailed(String)
    case userCancelled
    case stateMismatch
    case missingCode
    case invalidCallback
    case tokenExchangeFailed(Int, String)
    case refreshFailed
    case noRefreshToken
    case notSignedIn
    case keychainDeleteFailed

    var errorDescription: String? {
        switch self {
        case .discoveryFailed:
            return "Could not reach the blog OAuth provider."
        case .registrationFailed(let detail):
            return "Client registration failed: \(detail)"
        case .userCancelled:
            return "Sign in was cancelled."
        case .stateMismatch:
            return "Sign in failed: state mismatch."
        case .missingCode:
            return "Sign in failed: no authorization code returned."
        case .invalidCallback:
            return "Sign in failed: invalid callback."
        case .tokenExchangeFailed(let code, let detail):
            return "Token exchange failed (\(code)): \(detail)"
        case .refreshFailed:
            return "Could not refresh the blog session. Please sign in again."
        case .noRefreshToken:
            return "No refresh token available. Please sign in again."
        case .notSignedIn:
            return "Not signed in to the blog."
        case .keychainDeleteFailed:
            return "Could not remove the saved blog session from the Keychain."
        }
    }
}

// MARK: - Service

actor BlogOAuthService: BlogAccessTokenProviding {
    static let shared = BlogOAuthService()

    private let session: URLSession
    private let defaults: UserDefaults
    private let keychainAccount: String

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        keychainAccount: String = Constants.BlogOAuth.tokensKeychainAccount
    ) {
        self.session = session
        self.defaults = defaults
        self.keychainAccount = keychainAccount
    }

    // MARK: Public API

    /// Run the full interactive sign-in flow and persist the resulting tokens.
    @discardableResult
    func signIn() async throws -> BlogOAuthTokens {
        let config = await loadOIDCConfig()
        let clientID = try await registerClientIfNeeded(config: config)

        let pkce = Self.generatePKCE()
        let state = Self.randomURLSafeString(byteCount: 32)
        let authURL = buildAuthorizationURL(
            config: config, clientID: clientID, challenge: pkce.challenge, state: state
        )

        let authenticator = await BlogOAuthWebAuthenticator()
        let callbackURL = try await authenticator.authenticate(
            url: authURL, callbackScheme: Constants.BlogOAuth.callbackScheme
        )

        let (code, returnedState) = try parseCallback(callbackURL)
        guard returnedState == state else { throw BlogOAuthError.stateMismatch }

        var tokens = try await exchangeCode(
            code: code, verifier: pkce.verifier, clientID: clientID, config: config
        )
        tokens.accountEmail = await fetchUserEmail(accessToken: tokens.accessToken, config: config)
        try saveTokensToKeychain(tokens)
        return tokens
    }

    /// Delete the persisted tokens (does not revoke server-side).
    /// - Throws: `BlogOAuthError.keychainDeleteFailed` if the item could not be removed.
    func signOut() throws {
        guard deleteTokensFromKeychain() else {
            throw BlogOAuthError.keychainDeleteFailed
        }
    }

    /// The persisted account, without any network call. For settings display.
    func currentAccount() -> BlogOAuthTokens? {
        loadTokensFromKeychain()
    }

    /// A valid access token, refreshing if expiring. `nil` when not signed in.
    func validAccessToken() async throws -> String? {
        guard let tokens = loadTokensFromKeychain() else { return nil }
        guard tokens.isExpired || tokens.isAboutToExpire else {
            return tokens.accessToken
        }
        guard let refreshToken = tokens.refreshToken else {
            // No way to refresh; keep returning the (possibly expired) token and let the
            // server 401 surface a re-sign-in prompt.
            return tokens.accessToken
        }
        let config = await loadOIDCConfig()
        let refreshed = try await performRefresh(
            refreshToken: refreshToken, clientID: tokens.clientID, config: config, previous: tokens
        )
        try saveTokensToKeychain(refreshed)
        return refreshed.accessToken
    }

    // MARK: OIDC discovery

    private func loadOIDCConfig() async -> BlogOIDCConfig {
        struct Discovery: Decodable {
            let authorization_endpoint: String?
            let token_endpoint: String?
            let registration_endpoint: String?
            let userinfo_endpoint: String?
        }
        let fallback = BlogOIDCConfig(
            authorizationEndpoint: Constants.BlogOAuth.authorizeURL,
            tokenEndpoint: Constants.BlogOAuth.tokenURL,
            registrationEndpoint: Constants.BlogOAuth.registerURL,
            userinfoEndpoint: Constants.BlogOAuth.userinfoURL
        )
        do {
            let (data, response) = try await session.data(from: Constants.BlogOAuth.discoveryURL)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200,
                  let decoded = try? JSONDecoder().decode(Discovery.self, from: data) else {
                Logger.api.error("Blog OIDC discovery unusable (HTTP \(status)), using fallback endpoints")
                return fallback
            }
            return BlogOIDCConfig(
                authorizationEndpoint: decoded.authorization_endpoint.flatMap(URL.init) ?? fallback.authorizationEndpoint,
                tokenEndpoint: decoded.token_endpoint.flatMap(URL.init) ?? fallback.tokenEndpoint,
                registrationEndpoint: decoded.registration_endpoint.flatMap(URL.init) ?? fallback.registrationEndpoint,
                userinfoEndpoint: decoded.userinfo_endpoint.flatMap(URL.init) ?? fallback.userinfoEndpoint
            )
        } catch {
            Logger.api.info("Blog OIDC discovery failed, using fallback endpoints: \(error.localizedDescription)")
            return fallback
        }
    }

    // MARK: Dynamic client registration

    private func registerClientIfNeeded(config: BlogOIDCConfig) async throws -> String {
        if let existing = defaults.string(forKey: Constants.BlogOAuth.clientIDDefaultsKey), !existing.isEmpty {
            // A dynamically-registered client can vanish server-side (e.g. provider
            // data reset). The authorize endpoint then 302s to an `error=invalid_client`
            // page on the *http* origin — outside the `claudemeter://` callback scheme —
            // so the interactive session can't surface it. Probe the cached client_id
            // up-front and re-register if it's no longer recognised.
            if await cachedClientIsValid(existing, config: config) {
                return existing
            }
            Logger.api.info("Blog OAuth: cached client_id no longer valid, re-registering")
            defaults.removeObject(forKey: Constants.BlogOAuth.clientIDDefaultsKey)
        }
        guard let registrationURL = config.registrationEndpoint else {
            throw BlogOAuthError.registrationFailed("no registration endpoint")
        }

        struct RegistrationRequest: Encodable {
            let client_name = Constants.BlogOAuth.clientName
            let redirect_uris = [Constants.BlogOAuth.redirectURI]
            let token_endpoint_auth_method = "none"
            let grant_types = ["authorization_code", "refresh_token"]
            let response_types = ["code"]
            let scope = Constants.BlogOAuth.scopes
        }

        var request = URLRequest(url: registrationURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // Better Auth rejects requests with a missing/null Origin (MISSING_OR_NULL_ORIGIN).
        // URLSession sends no Origin by default, so set it to the trusted issuer origin.
        request.setValue(Constants.BlogOAuth.issuer, forHTTPHeaderField: "Origin")
        request.httpBody = try JSONEncoder().encode(RegistrationRequest())

        // Block redirects: RFC 7591 registration returns 201/200 with a JSON body, never a
        // 3xx. If the issuer redirects (e.g. to add a trailing slash or a canonical host),
        // following it would land on a non-JSON 200 page and silently break `client_id`
        // extraction — the original "client_id never persists" bug.
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: NoRedirectDelegate())
        } catch {
            Logger.api.error("Blog OAuth: registration request threw: \(error.localizedDescription, privacy: .public)")
            throw BlogOAuthError.registrationFailed("network error: \(error.localizedDescription)")
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? -1
        let contentType = http?.value(forHTTPHeaderField: "content-type") ?? "unknown"
        guard (200..<300).contains(status),
              let clientID = Self.extractClientID(from: data) else {
            let detail = String(data: data, encoding: .utf8) ?? "<non-UTF-8 \(data.count) bytes>"
            Logger.api.error("Blog OAuth: registration failed HTTP \(status) (content-type: \(contentType, privacy: .public)): \(detail, privacy: .public)")
            throw BlogOAuthError.registrationFailed("HTTP \(status): \(detail)")
        }
        defaults.set(clientID, forKey: Constants.BlogOAuth.clientIDDefaultsKey)
        Logger.api.info("Blog OAuth: registered client_id (\(clientID.prefix(8))…)")
        return clientID
    }

    /// Extracts the dynamically-registered `client_id` from a registration response.
    ///
    /// RFC 7591 returns it at the top level (`{"client_id":"…"}). Some providers wrap it
    /// (`{"client":{"client_id":"…"}}`) or camelCase it (`clientId`). We accept any of
    /// those so a provider-side shape change doesn't silently break sign-in.
    nonisolated static func extractClientID(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let id = object["client_id"] as? String, !id.isEmpty { return id }
        if let client = object["client"] as? [String: Any],
           let id = client["client_id"] as? String, !id.isEmpty
        {
            return id
        }
        if let id = object["clientId"] as? String, !id.isEmpty { return id }
        return nil
    }

    /// Probe the authorization endpoint to confirm a cached `client_id` still exists.
    ///
    /// For an unknown client the provider replies `302 → …?error=invalid_client`; for a
    /// known one it replies `302 → /login?…` (no session) or another non-error redirect.
    /// We block the redirect and inspect the `Location` header so a single un-followed
    /// request is enough — no page load, no session cookies.
    private func cachedClientIsValid(_ clientID: String, config: BlogOIDCConfig) async -> Bool {
        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Constants.BlogOAuth.redirectURI),
            URLQueryItem(name: "scope", value: Constants.BlogOAuth.scopes)
        ]
        guard let url = components.url else { return false }
        var request = URLRequest(url: url)
        request.setValue(Constants.BlogOAuth.issuer, forHTTPHeaderField: "Origin")
        request.timeoutInterval = Constants.requestTimeout

        do {
            let (_, response) = try await session.data(for: request, delegate: NoRedirectDelegate())
            guard let http = response as? HTTPURLResponse,
                  let location = http.value(forHTTPHeaderField: "Location") else {
                // No redirect captured (e.g. a 2xx/4xx). Treat as inconclusive but usable;
                // a genuinely-broken client_id still surfaces in the interactive flow.
                return true
            }
            return !location.contains("error=invalid_client")
        } catch {
            // Network failure: don't force a re-registration over a transient error.
            return true
        }
    }

    // MARK: Authorization URL

    private func buildAuthorizationURL(
        config: BlogOIDCConfig, clientID: String, challenge: String, state: String
    ) -> URL {
        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Constants.BlogOAuth.redirectURI),
            URLQueryItem(name: "scope", value: Constants.BlogOAuth.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "resource", value: Constants.BlogOAuth.resource)
        ]
        return components.url!
    }

    private func parseCallback(_ url: URL) throws -> (code: String, state: String?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw BlogOAuthError.invalidCallback
        }
        let items = components.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw BlogOAuthError.tokenExchangeFailed(0, error)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw BlogOAuthError.missingCode
        }
        return (code, items.first(where: { $0.name == "state" })?.value)
    }

    // MARK: Token exchange & refresh

    private func exchangeCode(
        code: String, verifier: String, clientID: String, config: BlogOIDCConfig
    ) async throws -> BlogOAuthTokens {
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Constants.BlogOAuth.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
            "resource": Constants.BlogOAuth.resource
        ]
        let parsed = try await postTokenRequest(body: body, config: config)
        return BlogOAuthTokens(
            accessToken: parsed.accessToken,
            refreshToken: parsed.refreshToken,
            expiresAt: parsed.expiresAtMs,
            scope: parsed.scope,
            clientID: clientID,
            accountEmail: nil
        )
    }

    private func performRefresh(
        refreshToken: String, clientID: String, config: BlogOIDCConfig, previous: BlogOAuthTokens
    ) async throws -> BlogOAuthTokens {
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "resource": Constants.BlogOAuth.resource
        ]
        let parsed: ParsedTokenResponse
        do {
            parsed = try await postTokenRequest(body: body, config: config)
        } catch {
            throw BlogOAuthError.refreshFailed
        }
        return BlogOAuthTokens(
            accessToken: parsed.accessToken,
            // Persist a rotated refresh token if returned, else keep the previous one.
            refreshToken: parsed.refreshToken ?? previous.refreshToken,
            expiresAt: parsed.expiresAtMs,
            scope: parsed.scope ?? previous.scope,
            clientID: clientID,
            accountEmail: previous.accountEmail
        )
    }

    private struct ParsedTokenResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresAtMs: Double?
        let scope: String?
    }

    private func postTokenRequest(body: [String: String], config: BlogOIDCConfig) async throws -> ParsedTokenResponse {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.setValue(Constants.BlogOAuth.issuer, forHTTPHeaderField: "Origin")
        request.httpBody = body
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        request.timeoutInterval = Constants.requestTimeout

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw BlogOAuthError.tokenExchangeFailed(status, String(data: data, encoding: .utf8) ?? "")
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
            let scope: String?
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAtMs: Double? = decoded.expires_in.map {
            (Date().timeIntervalSince1970 + Double($0)) * 1000
        }
        return ParsedTokenResponse(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAtMs: expiresAtMs,
            scope: decoded.scope
        )
    }

    // MARK: Userinfo (best-effort)

    private func fetchUserEmail(accessToken: String, config: BlogOIDCConfig) async -> String? {
        guard let userinfoURL = config.userinfoEndpoint else { return nil }
        var request = URLRequest(url: userinfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        request.setValue(Constants.BlogOAuth.issuer, forHTTPHeaderField: "Origin")
        struct UserInfo: Decodable { let email: String? }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(UserInfo.self, from: data) else {
            return nil
        }
        return decoded.email
    }

    // MARK: PKCE helpers

    struct PKCE { let verifier: String; let challenge: String }

    static func generatePKCE() -> PKCE {
        let verifier = randomURLSafeString(byteCount: 64)
        let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
        return PKCE(verifier: verifier, challenge: base64URL(challengeData))
    }

    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Keychain storage (via `/usr/bin/security` CLI)
    //
    // Mirrors `BlogUsageSyncService`: the token blob is stored in the login Keychain via
    // the Apple-signed `security` binary so the "Always Allow" grant survives rebuilds of
    // the unsigned (ad-hoc) app. An in-process `SecItem*` accessor would re-prompt on
    // every launch.

    private func loadTokensFromKeychain() -> BlogOAuthTokens? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", KeychainHelper.service,
            "-a", keychainAccount,
            "-w"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Logger.keychain.error("security find-generic-password (oauth) failed to run: \(error.localizedDescription)")
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let jsonData = json.data(using: .utf8),
              let tokens = try? JSONDecoder().decode(BlogOAuthTokens.self, from: jsonData) else {
            return nil
        }
        return tokens
    }

    private func saveTokensToKeychain(_ tokens: BlogOAuthTokens) throws {
        let jsonData = try JSONEncoder().encode(tokens)
        let json = String(data: jsonData, encoding: .utf8) ?? ""
        let escaped = json
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let service = KeychainHelper.service
        let account = keychainAccount
        let command = "add-generic-password -U -s \(service) -a \(account) -w \"\(escaped)\" -T /usr/bin/security\n"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["-i"]
        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(Data(command.utf8))
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        guard loadTokensFromKeychain() == tokens else {
            let stderr = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = stderr.isEmpty ? "keychain write could not be verified" : stderr
            Logger.keychain.error("security add-generic-password (oauth) failed: \(message)")
            throw NSError(
                domain: "BlogOAuth.Keychain",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    /// Delete every matching keychain item and confirm none remain.
    ///
    /// `security delete-generic-password` removes only one matching item per call, so a
    /// keychain that accumulated duplicates (e.g. an item left by an older in-process build
    /// alongside one written via the CLI) would still report "signed in" after a single
    /// delete — making the "Sign Out" button appear to do nothing. Loop until the lookup
    /// comes back empty, then verify, so the UI can trust the result.
    @discardableResult
    private func deleteTokensFromKeychain() -> Bool {
        // Bounded loop: each pass removes at most one item; stop once none remain.
        for _ in 0..<16 {
            guard loadTokensFromKeychain() != nil else { return true }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = [
                "delete-generic-password",
                "-s", KeychainHelper.service,
                "-a", keychainAccount
            ]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                Logger.keychain.error("security delete-generic-password (oauth) failed to run: \(error.localizedDescription)")
                return false
            }
            process.waitUntilExit()

            // A non-zero status with the item still present means we made no progress.
            if process.terminationStatus != 0, loadTokensFromKeychain() != nil {
                Logger.keychain.error("security delete-generic-password (oauth) returned status \(process.terminationStatus)")
                return false
            }
        }
        return loadTokensFromKeychain() == nil
    }
}

// MARK: - Redirect-blocking session delegate

/// Stops `URLSession` from following redirects so the raw `Location` header of a 302
/// can be inspected. Used to validate a cached `client_id` without loading any page.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

// MARK: - OIDC config

nonisolated struct BlogOIDCConfig: Sendable {
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let registrationEndpoint: URL?
    let userinfoEndpoint: URL?
}

// MARK: - Web authenticator (ASWebAuthenticationSession)

@MainActor
final class BlogOAuthWebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var anchorWindow: NSWindow?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    if let asError = error as? ASWebAuthenticationSessionError,
                       asError.code == .canceledLogin {
                        continuation.resume(throwing: BlogOAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: BlogOAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: BlogOAuthError.invalidCallback)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            return window
        }
        // LSUIElement menu bar app: no normal window. Provide a transient anchor.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.center()
        anchorWindow = window
        return window
    }
}
#endif
