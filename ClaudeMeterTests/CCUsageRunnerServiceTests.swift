//
//  CCUsageRunnerServiceTests.swift
//  ClaudeMeterTests
//

import Foundation
import Testing
@testable import ClaudeMeter

#if os(macOS)
@Suite("CCUsageRunnerService")
struct CCUsageRunnerServiceTests {
    @Test func commandUsesUnscopedDailyReport() {
        let runner = CCUsageRunnerService.RunnerCandidate(
            kind: .pnx,
            executableURL: URL(fileURLWithPath: "/tmp/pnx")
        )

        let invocation = CCUsageRunnerService.makeInvocation(
            runner: runner,
            since: "20260601",
            timezone: "Asia/Singapore",
            environment: ["PATH": "/tmp"]
        )

        #expect(invocation.arguments == [
            "ccusage@\(CCUsageRunnerService.pinnedPackageVersion)",
            "daily",
            "--json",
            "--since",
            "20260601",
            "--order",
            "desc",
            "--timezone",
            "Asia/Singapore"
        ])
        #expect(!invocation.arguments.contains("claude"))
    }

    @Test func fallbackTriesPnxThenPnpxThenPnpmDlx() async throws {
        let recorder = InvocationRecorder()
        let candidates = Self.allFallbackCandidates()

        let service = CCUsageRunnerService(
            runnerCandidates: { candidates },
            commandExecutor: { invocation, _ in
                await recorder.record(invocation)
                if invocation.runner.kind == .pnpmDlx {
                    return Self.validResult()
                }
                return CCUsageRunnerService.CommandResult(
                    exitCode: 1,
                    stdout: "",
                    stderr: "missing runner"
                )
            }
        )

        let result = try await service.fetchUsage()
        let runnerNames = await recorder.runnerNames()

        #expect(runnerNames == ["pnx", "pnpx", "pnpm dlx"])
        #expect(result.snapshot.dataSource == .ccusage(runner: "pnpm dlx"))
    }

    @Test func mapsUnscopedJsonAndPreservesDetectedProviders() async throws {
        let service = CCUsageRunnerService(
            runnerCandidates: {
                [
                    CCUsageRunnerService.RunnerCandidate(
                        kind: .pnx,
                        executableURL: URL(fileURLWithPath: "/tmp/pnx")
                    )
                ]
            },
            commandExecutor: { _, _ in Self.validResult() }
        )

        let result = try await service.fetchUsage()
        let providerIds = result.snapshot.detectedProviders.map(\.id)

        #expect(providerIds == ["claude", "codex", "opencode"])
        #expect(result.snapshot.last30Days.tokens.inputTokens == 300)
        #expect(result.snapshot.last30Days.tokens.outputTokens == 30)
        #expect(result.snapshot.last30Days.costUSD == 1.5)
        #expect(result.snapshot.byModel["claude-opus-4-8"]?.totalTokens == 115)
        #expect(result.snapshot.byModel["gpt-5.5"]?.totalTokens == 215)
    }

    @Test func defaultRunnerResolutionPrefersPnx() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for name in ["pnpm", "pnpx", "pnx"] {
            let file = tempDir.appendingPathComponent(name)
            try "#!/bin/sh\nexit 0\n".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: file.path
            )
        }

        let candidates = CCUsageRunnerService.defaultRunnerCandidates(
            environment: ["PATH": tempDir.path]
        )

        #expect(Array(candidates.map(\.displayName).prefix(3)) == ["pnx", "pnpx", "pnpm dlx"])
    }

    private static func allFallbackCandidates() -> [CCUsageRunnerService.RunnerCandidate] {
        [
            CCUsageRunnerService.RunnerCandidate(
                kind: .pnx,
                executableURL: URL(fileURLWithPath: "/tmp/pnx")
            ),
            CCUsageRunnerService.RunnerCandidate(
                kind: .pnpx,
                executableURL: URL(fileURLWithPath: "/tmp/pnpx")
            ),
            CCUsageRunnerService.RunnerCandidate(
                kind: .pnpmDlx,
                executableURL: URL(fileURLWithPath: "/tmp/pnpm")
            )
        ]
    }

    private static func validResult() -> CCUsageRunnerService.CommandResult {
        CCUsageRunnerService.CommandResult(
            exitCode: 0,
            stdout: """
            {
              "daily": [
                {
                  "agent": "all",
                  "period": "\(todayPeriod())",
                  "inputTokens": 300,
                  "outputTokens": 30,
                  "cacheCreationTokens": 0,
                  "cacheReadTokens": 0,
                  "totalCost": 1.5,
                  "metadata": {
                    "agents": ["claude", "codex", "opencode"]
                  },
                  "modelBreakdowns": [
                    {
                      "modelName": "claude-opus-4-8",
                      "inputTokens": 100,
                      "outputTokens": 15,
                      "cacheCreationTokens": 0,
                      "cacheReadTokens": 0,
                      "cost": 1.0
                    },
                    {
                      "modelName": "gpt-5.5",
                      "inputTokens": 200,
                      "outputTokens": 15,
                      "cacheCreationTokens": 0,
                      "cacheReadTokens": 0,
                      "cost": 0.5
                    }
                  ]
                }
              ],
              "totals": {
                "inputTokens": 300,
                "outputTokens": 30,
                "cacheCreationTokens": 0,
                "cacheReadTokens": 0,
                "totalCost": 1.5,
                "totalTokens": 330
              }
            }
            """,
            stderr: ""
        )
    }

    private static func todayPeriod() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private actor InvocationRecorder {
    private var invocations: [CCUsageRunnerService.CommandInvocation] = []

    func record(_ invocation: CCUsageRunnerService.CommandInvocation) {
        invocations.append(invocation)
    }

    func runnerNames() -> [String] {
        invocations.map(\.runner.displayName)
    }
}
#endif
