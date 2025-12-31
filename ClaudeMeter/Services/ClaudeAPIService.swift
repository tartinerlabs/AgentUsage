//
//  ClaudeAPIService.swift
//  ClaudeMeter
//

import Foundation

actor ClaudeAPIService {
    enum APIError: LocalizedError {
        case unauthorized
        case networkError(Error)
        case invalidResponse
        case serverError(Int)

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
            }
        }
    }

    func fetchUsage(token: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Constants.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Constants.anthropicBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ClaudeMeter/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

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
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    private func parseUsageResponse(_ data: Data) throws -> UsageSnapshot {
        struct APIResponse: Decodable {
            let fiveHour: UsageWindowResponse?
            let sevenDay: UsageWindowResponse?

            enum CodingKeys: String, CodingKey {
                case fiveHour = "five_hour"
                case sevenDay = "seven_day"
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
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date()
            )
        } ?? UsageWindow(utilization: 0, resetsAt: Date())

        let weekly = response.sevenDay.map {
            UsageWindow(
                utilization: $0.utilization,
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date()
            )
        } ?? UsageWindow(utilization: 0, resetsAt: Date())

        return UsageSnapshot(
            session: session,
            weekly: weekly,
            fetchedAt: Date()
        )
    }
}
