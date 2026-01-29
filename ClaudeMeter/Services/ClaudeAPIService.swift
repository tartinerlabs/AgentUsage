//
//  ClaudeAPIService.swift
//  ClaudeMeter
//

import Foundation
import ClaudeMeterKit
import OSLog

actor ClaudeAPIService: APIServiceProtocol {
    enum APIError: LocalizedError {
        case unauthorized
        case networkError(Error)
        case invalidResponse
        case serverError(Int)
        case rateLimited(retryAfter: TimeInterval?)
        case serviceUnavailable
        case maxRetriesExceeded

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Unauthorized. Please re-authenticate with Claude CLI."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from server."
            case .serverError(let code):
                return "Server error: \(code)"
            case .rateLimited(let retryAfter):
                if let seconds = retryAfter {
                    return "Rate limited. Try again in \(Int(seconds)) seconds."
                }
                return "Rate limited. Please try again later."
            case .serviceUnavailable:
                return "Service temporarily unavailable."
            case .maxRetriesExceeded:
                return "Failed after multiple retry attempts."
            }
        }

        /// Whether this error should trigger a retry
        var isRetryable: Bool {
            switch self {
            case .networkError, .rateLimited, .serviceUnavailable:
                return true
            case .serverError(let code):
                // Retry on 5xx server errors (except 501 Not Implemented)
                return code >= 500 && code != 501
            case .unauthorized, .invalidResponse, .maxRetriesExceeded:
                return false
            }
        }
    }

    func fetchUsage(token: String) async throws -> UsageSnapshot {
        var lastError: APIError?

        for attempt in 0..<Constants.maxRetryAttempts {
            do {
                return try await performRequest(token: token)
            } catch let error as APIError {
                lastError = error

                // Don't retry non-retryable errors
                guard error.isRetryable else {
                    throw error
                }

                // Calculate delay for next retry
                let delay = calculateRetryDelay(attempt: attempt, error: error)

                // Don't wait after the last attempt
                if attempt < Constants.maxRetryAttempts - 1 {
                    Logger.api.info("Request failed (attempt \(attempt + 1)/\(Constants.maxRetryAttempts)): \(error.localizedDescription). Retrying in \(String(format: "%.1f", delay))s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        Logger.api.error("Request failed after \(Constants.maxRetryAttempts) attempts")
        throw lastError ?? APIError.maxRetriesExceeded
    }

    /// Perform a single API request without retry logic
    private func performRequest(token: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Constants.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Constants.anthropicBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ClaudeMeter/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = Constants.requestTimeout

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseUsageResponse(data)
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            // Extract Retry-After header if present
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) }
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 503:
            throw APIError.serviceUnavailable
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Calculate retry delay with exponential backoff
    private func calculateRetryDelay(attempt: Int, error: APIError) -> TimeInterval {
        // For rate limiting, use Retry-After header if available
        if case .rateLimited(let retryAfter) = error, let seconds = retryAfter {
            return seconds
        }

        // Exponential backoff: 1s, 2s, 4s, etc.
        let baseDelay = Constants.initialRetryDelay
        let multiplier = pow(Constants.retryBackoffMultiplier, Double(attempt))
        return baseDelay * multiplier
    }

    private func parseUsageResponse(_ data: Data) throws -> UsageSnapshot {
        // Debug: Log raw API response to see all available fields
        #if DEBUG
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            Logger.api.debug("Claude API Response:\n\(prettyString)")
        }
        #endif

        struct APIResponse: Decodable {
            let fiveHour: UsageWindowResponse?
            let sevenDay: UsageWindowResponse?       // Default weekly = Opus limit
            let sevenDaySonnet: UsageWindowResponse? // Separate Sonnet limit

            enum CodingKeys: String, CodingKey {
                case fiveHour = "five_hour"
                case sevenDay = "seven_day"
                case sevenDaySonnet = "seven_day_sonnet"
            }
        }

        struct UsageWindowResponse: Decodable {
            let utilization: Double
            let resetsAt: String

            enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(APIResponse.self, from: data)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let session = response.fiveHour.map {
            UsageWindow(
                utilization: $0.utilization,
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                windowType: .session
            )
        } ?? UsageWindow(utilization: 0, resetsAt: Date(), windowType: .session)

        // seven_day is now the default weekly limit (Opus)
        let opus = response.sevenDay.map {
            UsageWindow(
                utilization: $0.utilization,
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                windowType: .opus
            )
        } ?? UsageWindow(utilization: 0, resetsAt: Date(), windowType: .opus)

        // Separate Sonnet limit (if available)
        let sonnet = response.sevenDaySonnet.map {
            UsageWindow(
                utilization: $0.utilization,
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                windowType: .sonnet
            )
        }

        return UsageSnapshot(
            session: session,
            opus: opus,
            sonnet: sonnet,
            fetchedAt: Date()
        )
    }
}
