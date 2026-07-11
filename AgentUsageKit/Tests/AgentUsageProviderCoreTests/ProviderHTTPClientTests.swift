import AgentUsageProviderCore
import Foundation
import Testing

@Suite("Provider HTTP safety")
struct ProviderHTTPClientTests {
    @Test func allowsSameOriginHTTPSRedirect() throws {
        let original = try #require(URL(string: "https://example.com/start"))
        let redirected = try #require(URL(string: "https://example.com/next"))
        let request = URLRequest(url: redirected)
        #expect(ProviderHTTPClient.guardedRedirect(originalURL: original, proposedRequest: request) != nil)
    }

    @Test func rejectsCrossOriginAndDowngradeRedirects() throws {
        let original = try #require(URL(string: "https://example.com/start"))
        let crossOrigin = URLRequest(url: try #require(URL(string: "https://attacker.example/next")))
        let downgrade = URLRequest(url: try #require(URL(string: "http://example.com/next")))
        #expect(ProviderHTTPClient.guardedRedirect(originalURL: original, proposedRequest: crossOrigin) == nil)
        #expect(ProviderHTTPClient.guardedRedirect(originalURL: original, proposedRequest: downgrade) == nil)
    }
}
