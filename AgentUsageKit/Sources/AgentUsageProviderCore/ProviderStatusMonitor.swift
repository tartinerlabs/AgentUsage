import AgentUsageKit
import Foundation

public enum ProviderServiceHealth: String, Codable, Sendable {
    case operational
    case incident
    case unknown
}

public struct ProviderServiceStatus: Codable, Sendable {
    public let provider: Provider
    public let health: ProviderServiceHealth
    public let checkedAt: Date

    public init(provider: Provider, health: ProviderServiceHealth, checkedAt: Date) {
        self.provider = provider
        self.health = health
        self.checkedAt = checkedAt
    }
}

/// Polls provider-owned Statuspage endpoints independently from quota fetches.
/// A status incident is context only; this type never manufactures a provider
/// usage success or failure.
public actor ProviderStatusMonitor {
    private let transport: any ProviderHTTPTransport
    private let cacheDuration: TimeInterval
    private var cache: [Provider: ProviderServiceStatus] = [:]

    public init(
        transport: any ProviderHTTPTransport = ProviderHTTPClient(),
        cacheDuration: TimeInterval = 5 * 60
    ) {
        self.transport = transport
        self.cacheDuration = cacheDuration
    }

    public func status(
        for provider: Provider,
        url: URL,
        now: Date = Date()
    ) async -> ProviderServiceStatus {
        if let cached = cache[provider], now.timeIntervalSince(cached.checkedAt) < cacheDuration {
            return cached
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("AgentUsage/1.0", forHTTPHeaderField: "User-Agent")
        let health: ProviderServiceHealth
        do {
            let response = try await transport.response(for: request, retryPolicy: .transientIdempotent)
            guard (200..<300).contains(response.statusCode),
                  let payload = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                  let status = payload["status"] as? [String: Any],
                  let indicator = status["indicator"] as? String else {
                health = .unknown
                let result = ProviderServiceStatus(provider: provider, health: health, checkedAt: now)
                cache[provider] = result
                return result
            }
            health = indicator == "none" ? .operational : .incident
        } catch {
            health = .unknown
        }
        let result = ProviderServiceStatus(provider: provider, health: health, checkedAt: now)
        cache[provider] = result
        return result
    }
}
