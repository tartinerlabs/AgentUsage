// Derived in part from steipete/CodexBar ProviderHTTPClient.swift.
// Upstream commit: 98de97833505a6213ec2cf3c2c6d528443b77d8d (MIT).

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ProviderHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

#if !os(Linux)
extension URLSession: ProviderHTTPTransport {}
#endif

public struct ProviderHTTPResponse: Sendable {
    public let data: Data
    public let response: HTTPURLResponse

    public var statusCode: Int { response.statusCode }
}

public struct ProviderHTTPRetryPolicy: Sendable {
    public let maxRetries: Int
    public let retryableStatusCodes: Set<Int>
    public let retryableURLErrorCodes: Set<URLError.Code>
    public let baseDelay: Duration
    public let maximumDelay: Duration

    public init(
        maxRetries: Int = 1,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableURLErrorCodes: Set<URLError.Code> = [
            .timedOut, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed,
        ],
        baseDelay: Duration = .seconds(1),
        maximumDelay: Duration = .seconds(10)
    ) {
        self.maxRetries = max(0, maxRetries)
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableURLErrorCodes = retryableURLErrorCodes
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
    }

    public static let transientIdempotent = ProviderHTTPRetryPolicy()
    public static let disabled = ProviderHTTPRetryPolicy(
        maxRetries: 0,
        retryableStatusCodes: [],
        retryableURLErrorCodes: []
    )
}

extension ProviderHTTPTransport {
    public func response(
        for request: URLRequest,
        retryPolicy: ProviderHTTPRetryPolicy = .disabled
    ) async throws -> ProviderHTTPResponse {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                let result = ProviderHTTPResponse(data: data, response: http)
                guard canRetry(request, attempt: attempt, policy: retryPolicy),
                      retryPolicy.retryableStatusCodes.contains(http.statusCode)
                else { return result }
                try await sleepBeforeRetry(attempt: attempt, response: http, policy: retryPolicy)
                attempt += 1
            } catch {
                guard canRetry(request, attempt: attempt, policy: retryPolicy),
                      let urlError = error as? URLError,
                      retryPolicy.retryableURLErrorCodes.contains(urlError.code)
                else { throw error }
                try await sleepBeforeRetry(attempt: attempt, response: nil, policy: retryPolicy)
                attempt += 1
            }
        }
    }

    private func canRetry(
        _ request: URLRequest,
        attempt: Int,
        policy: ProviderHTTPRetryPolicy
    ) -> Bool {
        guard attempt < policy.maxRetries else { return false }
        let method = request.httpMethod?.uppercased() ?? "GET"
        return ["GET", "HEAD", "OPTIONS"].contains(method)
    }

    private func sleepBeforeRetry(
        attempt: Int,
        response: HTTPURLResponse?,
        policy: ProviderHTTPRetryPolicy
    ) async throws {
        let maximum = policy.maximumDelay.timeInterval
        let requested = response?
            .value(forHTTPHeaderField: "Retry-After")
            .flatMap(TimeInterval.init) ?? pow(2, Double(attempt)) * policy.baseDelay.timeInterval
        try await Task.sleep(for: .seconds(min(maximum, max(0, requested))))
    }
}

public final class ProviderHTTPClient: NSObject, ProviderHTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private let session: URLSession

    public override convenience init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        #if !os(Linux)
        configuration.waitsForConnectivity = false
        #endif
        self.init(configuration: configuration)
    }

    public init(configuration: URLSessionConfiguration) {
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        super.init()
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request, delegate: self)
    }

    public func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(Self.guardedRedirect(
            originalURL: task.originalRequest?.url,
            proposedRequest: request
        ))
    }

    public static func guardedRedirect(
        originalURL: URL?,
        proposedRequest: URLRequest
    ) -> URLRequest? {
        guard let originalURL, let redirectedURL = proposedRequest.url,
              originalURL.scheme?.lowercased() == "https",
              redirectedURL.scheme?.lowercased() == "https",
              originalURL.host?.lowercased() == redirectedURL.host?.lowercased(),
              normalizedPort(originalURL) == normalizedPort(redirectedURL)
        else { return nil }
        return proposedRequest
    }

    private static func normalizedPort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
