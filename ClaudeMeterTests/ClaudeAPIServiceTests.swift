//
//  ClaudeAPIServiceTests.swift
//  ClaudeMeterTests
//
//  Tests for ClaudeAPIService JSON parsing and response handling
//

import Testing
import Foundation
@testable import ClaudeMeter
@testable import ClaudeMeterKit

// MARK: - ClaudeAPIService Response Parsing Tests

@Suite("ClaudeAPIService")
struct ClaudeAPIServiceTests {

    // MARK: - API Error Tests

    @Test func unauthorizedErrorDescription() {
        let error = ClaudeAPIService.APIError.unauthorized
        #expect(error.errorDescription?.contains("Unauthorized") == true)
        #expect(error.errorDescription?.contains("re-authenticate") == true)
    }

    @Test func networkErrorDescription() {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [
            NSLocalizedDescriptionKey: "The Internet connection appears to be offline."
        ])
        let error = ClaudeAPIService.APIError.networkError(underlying)
        #expect(error.errorDescription?.contains("Network error") == true)
    }

    @Test func invalidResponseErrorDescription() {
        let error = ClaudeAPIService.APIError.invalidResponse
        #expect(error.errorDescription?.contains("Invalid response") == true)
    }

    @Test func serverErrorDescription() {
        let error = ClaudeAPIService.APIError.serverError(500)
        #expect(error.errorDescription?.contains("500") == true)
    }
}

// MARK: - API Response Parsing Tests

/// Tests for parsing the Claude API usage response JSON
/// These tests verify the parsing logic without making network requests
@Suite("API Response Parsing")
struct APIResponseParsingTests {

    /// Helper to parse JSON response using the same logic as ClaudeAPIService
    private func parseUsageResponse(_ json: String) throws -> UsageSnapshot {
        struct APIResponse: Decodable {
            let fiveHour: UsageWindowResponse?
            let sevenDay: UsageWindowResponse?
            let sevenDaySonnet: UsageWindowResponse?

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

        let data = json.data(using: .utf8)!
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

        let opus = response.sevenDay.map {
            UsageWindow(
                utilization: $0.utilization,
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                windowType: .opus
            )
        } ?? UsageWindow(utilization: 0, resetsAt: Date(), windowType: .opus)

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

    @Test func parsesCompleteResponse() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 45.5,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 32.1,
                "resets_at": "2024-01-20T00:00:00.000Z"
            },
            "seven_day_sonnet": {
                "utilization": 28.7,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 45.5)
        #expect(snapshot.session.windowType == .session)
        #expect(snapshot.opus.utilization == 32.1)
        #expect(snapshot.opus.windowType == .opus)
        #expect(snapshot.sonnet?.utilization == 28.7)
        #expect(snapshot.sonnet?.windowType == .sonnet)
    }

    @Test func parsesResponseWithoutSonnet() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 50.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 40.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 50.0)
        #expect(snapshot.opus.utilization == 40.0)
        #expect(snapshot.sonnet == nil)
    }

    @Test func parsesResponseAt100Percent() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 100.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 100.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.isAtLimit == true)
        #expect(snapshot.opus.isAtLimit == true)
    }

    @Test func parsesResponseWithZeroUtilization() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 0.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 0.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 0.0)
        #expect(snapshot.opus.utilization == 0.0)
        #expect(snapshot.session.isAtLimit == false)
    }

    @Test func parsesEmptyResponse() throws {
        let json = "{}"

        let snapshot = try parseUsageResponse(json)

        // Should default to zero utilization
        #expect(snapshot.session.utilization == 0)
        #expect(snapshot.opus.utilization == 0)
        #expect(snapshot.sonnet == nil)
    }

    @Test func parsesISO8601DateWithFractionalSeconds() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 50.0,
                "resets_at": "2024-01-15T18:30:45.123Z"
            },
            "seven_day": {
                "utilization": 40.0,
                "resets_at": "2024-01-20T12:00:00.456Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        // Verify dates were parsed (not default Date())
        // The exact values depend on parsing, but they should be in 2024
        let calendar = Calendar.current
        let sessionYear = calendar.component(.year, from: snapshot.session.resetsAt)
        let opusYear = calendar.component(.year, from: snapshot.opus.resetsAt)

        #expect(sessionYear == 2024)
        #expect(opusYear == 2024)
    }

    @Test func handlesUtilizationAbove100() throws {
        // API might return values > 100 in edge cases (extra usage)
        let json = """
        {
            "five_hour": {
                "utilization": 105.5,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 110.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 105.5)
        #expect(snapshot.session.isAtLimit == true)
        #expect(snapshot.session.normalized == 1.0) // Clamped to 1.0
        #expect(snapshot.session.isUsingExtraUsage == true)
        #expect(snapshot.session.extraUsagePercent == 5)
        #expect(snapshot.opus.isUsingExtraUsage == true)
        #expect(snapshot.opus.extraUsagePercent == 10)
        #expect(snapshot.isExtraUsageActive == true)
    }

    @Test func handlesDecimalUtilization() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 33.333333,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 66.666666,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 33.333333)
        #expect(snapshot.session.percentUsed == 33) // Truncated
        #expect(snapshot.opus.utilization == 66.666666)
        #expect(snapshot.opus.percentUsed == 66)
    }

    // MARK: - Edge Case Tests

    @Test func handlesNegativeUtilization() throws {
        // API shouldn't return negative, but test defensive handling
        let json = """
        {
            "five_hour": {
                "utilization": -5.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 0.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        // Negative utilization is stored as-is (data model doesn't clamp)
        #expect(snapshot.session.utilization == -5.0)
        // normalized should clamp to 0
        #expect(snapshot.session.normalized == 0.0)
    }

    @Test func handlesVeryLargeUtilization() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 9999.99,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 100.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 9999.99)
        #expect(snapshot.session.isAtLimit == true)
        #expect(snapshot.session.normalized == 1.0) // Clamped
    }

    @Test func handlesExactBoundaryValues() throws {
        // Test exactly 75% (warning threshold) and 90% (critical threshold)
        let json = """
        {
            "five_hour": {
                "utilization": 75.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 90.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 75.0)
        #expect(snapshot.opus.utilization == 90.0)
    }

    @Test func snapshotFetchedAtIsReasonable() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 50.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 40.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let beforeParse = Date()
        let snapshot = try parseUsageResponse(json)
        let afterParse = Date()

        // fetchedAt should be between beforeParse and afterParse
        #expect(snapshot.fetchedAt >= beforeParse)
        #expect(snapshot.fetchedAt <= afterParse)
    }
}
