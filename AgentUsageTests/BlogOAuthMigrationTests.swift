//
//  BlogOAuthMigrationTests.swift
//  AgentUsageTests
//

#if os(macOS)
import Foundation
import Testing
@testable import AgentUsage

/// Verifies the one-time migration that moves blog OAuth tokens out of the file-based
/// login Keychain (where the `/usr/bin/security` CLI wrote them, and where rewriting the
/// item ACL prompted for the login password on every token refresh) into the
/// data-protection Keychain (governed by the `keychain-access-groups` entitlement, no ACL).
@Suite("Blog OAuth Keychain migration", .serialized)
struct BlogOAuthMigrationTests {
    @Test func migratesLegacyLoginKeychainTokensToDataProtection() async throws {
        let account = "BlogOAuthMigrationTest-\(UUID().uuidString)"
        let tokens = BlogOAuthTokens(
            accessToken: "legacy-access-token",
            refreshToken: "legacy-refresh-token",
            expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
            scope: "openid",
            clientID: "test-client",
            accountEmail: "tester@example.com"
        )
        let json = try String(decoding: JSONEncoder().encode(tokens), as: UTF8.self)

        defer {
            KeychainHelper.deleteString(account: account)
            Self.cliDelete(account: account)
        }

        // Seed a "legacy" item in the login Keychain exactly as the old CLI path did.
        // Creating a fresh item with -T sets its initial ACL and does not prompt.
        try #require(Self.cliAdd(json: json, account: account))
        try #require(Self.cliFind(account: account) == json, "precondition: legacy item present")

        let service = BlogOAuthService(keychainAccount: account)

        // currentAccount() -> loadTokensFromKeychain() -> migration.
        let migrated = await service.currentAccount()
        #expect(migrated == tokens)

        // The legacy login-Keychain item is removed...
        #expect(Self.cliFind(account: account) == nil)
        // ...and the value now lives in the data-protection Keychain.
        #expect(try KeychainHelper.loadString(account: account) == json)
    }

    // MARK: - `/usr/bin/security` helpers (login keychain)

    private static func cliAdd(json: String, account: String) -> Bool {
        let escaped = json
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let command = "add-generic-password -U -s \(KeychainHelper.service) "
            + "-a \(account) -w \"\(escaped)\" -T /usr/bin/security\n"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["-i"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return false }
        input.fileHandleForWriting.write(Data(command.utf8))
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()
        return cliFind(account: account) == json
    }

    private static func cliFind(account: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", KeychainHelper.service, "-a", account, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    private static func cliDelete(account: String) {
        for _ in 0..<16 where cliFind(account: account) != nil {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["delete-generic-password", "-s", KeychainHelper.service, "-a", account]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
    }
}
#endif
