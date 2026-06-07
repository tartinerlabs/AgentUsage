//
//  OpenCodeGoUsageService.swift
//  ClaudeMeter
//
//  OpenCode Go quota windows from the authenticated dashboard page.
//

#if os(macOS)
import Foundation
import ClaudeMeterKit
import OSLog

actor OpenCodeGoUsageService {
    nonisolated let provider: Provider = .openCode

    private let session: URLSession
    private let configProvider: @Sendable () -> DashboardConfig?
    private let now: @Sendable () -> Date

    init(
        session: URLSession = .shared,
        configProvider: @escaping @Sendable () -> DashboardConfig? = { DashboardConfig.load() },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.configProvider = configProvider
        self.now = now
    }

    func fetchSnapshot() async throws -> ProviderUsageSnapshot? {
        guard let config = configProvider() else { return nil }
        var request = URLRequest(url: config.dashboardURL)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(config.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            Logger.tokenUsage.warning("OpenCode Go dashboard request failed")
            return nil
        }

        guard let html = String(data: data, encoding: .utf8) else { return nil }
        return Self.parseDashboardHTML(html, now: now())
    }

    nonisolated static func parseDashboardHTML(_ html: String, now: Date) -> ProviderUsageSnapshot? {
        let text = html.replacingOccurrences(of: #"\""#, with: #"""#)
        let specs: [(field: String, type: UsageWindowType)] = [
            ("rollingUsage", .openCodeGoFiveHour),
            ("weeklyUsage", .openCodeGoWeekly),
            ("monthlyUsage", .openCodeGoMonthly)
        ]

        let windows = specs.compactMap { spec -> UsageWindow? in
            guard let usage = extractNumber(field: spec.field, key: "usagePercent", text: text),
                  let resetSeconds = extractNumber(field: spec.field, key: "resetInSec", text: text) else {
                return nil
            }
            return UsageWindow(
                utilization: usage,
                resetsAt: now.addingTimeInterval(max(0, resetSeconds)),
                windowType: spec.type
            )
        }

        guard !windows.isEmpty else { return nil }
        return ProviderUsageSnapshot(
            provider: .openCode,
            windows: windows,
            planName: "Go",
            fetchedAt: now
        )
    }

    private nonisolated static func extractNumber(field: String, key: String, text: String) -> Double? {
        let pattern = #"['\"]?# + NSRegularExpression.escapedPattern(for: field) + #"['\"]?\s*:\s*(?:\$R\[\d+\]\s*=\s*)?\{[^}]*?['\"]?# + NSRegularExpression.escapedPattern(for: key) + #"['\"]?\s*:\s*['\"]?(-?\d+(?:\.\d+)?)['\"]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }

    nonisolated struct DashboardConfig: Sendable, Equatable {
        let workspaceID: String
        let authCookie: String

        var dashboardURL: URL {
            URL(string: "https://opencode.ai/workspace/\(workspaceID)/go")!
        }

        var cookieHeader: String {
            authCookie.contains("auth=") ? authCookie : "auth=\(authCookie)"
        }

        static func load(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            fileManager: FileManager = .default,
            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        ) -> DashboardConfig? {
            if let workspaceID = normalizedWorkspaceID(environment["OPENCODE_GO_WORKSPACE_ID"]),
               let authCookie = environment["OPENCODE_GO_AUTH_COOKIE"],
               !authCookie.isEmpty {
                return DashboardConfig(workspaceID: workspaceID, authCookie: authCookie)
            }

            for url in configFileCandidates(environment: environment, homeDirectory: homeDirectory) {
                guard fileManager.fileExists(atPath: url.path),
                      let data = try? Data(contentsOf: url),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                let workspace = object["workspaceId"] as? String
                    ?? object["workspaceID"] as? String
                    ?? object["workspace_id"] as? String
                let cookie = object["authCookie"] as? String
                    ?? object["auth_cookie"] as? String
                    ?? object["cookie"] as? String
                if let workspaceID = normalizedWorkspaceID(workspace), let cookie, !cookie.isEmpty {
                    return DashboardConfig(workspaceID: workspaceID, authCookie: cookie)
                }
            }
            return nil
        }

        private static func configFileCandidates(environment: [String: String], homeDirectory: URL) -> [URL] {
            var urls: [URL] = []
            if let override = environment["OPENCODE_GO_CONFIG_FILE"], !override.isEmpty {
                urls.append(URL(fileURLWithPath: override))
            }
            if let xdgConfig = environment["XDG_CONFIG_HOME"], !xdgConfig.isEmpty {
                let base = URL(fileURLWithPath: xdgConfig)
                urls.append(base.appendingPathComponent("opencode-bar/opencode-go.json"))
                urls.append(base.appendingPathComponent("opencode-quota/opencode-go.json"))
            }
            urls.append(homeDirectory.appendingPathComponent(".config/opencode-bar/opencode-go.json"))
            urls.append(homeDirectory.appendingPathComponent(".config/opencode-quota/opencode-go.json"))
            urls.append(homeDirectory.appendingPathComponent("Library/Application Support/opencode-bar/opencode-go.json"))
            urls.append(homeDirectory.appendingPathComponent("Library/Application Support/opencode-quota/opencode-go.json"))
            return urls
        }

        private static func normalizedWorkspaceID(_ raw: String?) -> String? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            if raw.hasPrefix("wrk_") { return raw }
            if URL(string: raw) != nil, let range = raw.range(of: #"/workspace/([^/]+)"#, options: .regularExpression) {
                let match = String(raw[range])
                return match.replacingOccurrences(of: "/workspace/", with: "")
            }
            return nil
        }
    }
}
#endif
