@testable import AgentUsageProviderCore
import Foundation
import Testing

@Suite("Provider status context")
struct ProviderStatusMonitorTests {
    @Test("status incidents are parsed and cached independently")
    func parsesAndCaches() async throws {
        let transport = StatusTransport()
        let monitor = ProviderStatusMonitor(transport: transport)
        let url = try #require(URL(string: "https://status.example.com/api/v2/status.json"))
        let first = await monitor.status(for: .claude, url: url, now: Date(timeIntervalSince1970: 100))
        let second = await monitor.status(for: .claude, url: url, now: Date(timeIntervalSince1970: 200))
        #expect(first.health == .incident)
        #expect(second.health == .incident)
        #expect(await transport.requestCount == 1)
    }
}

private actor StatusTransport: ProviderHTTPTransport {
    private(set) var requestCount = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(#"{"status":{"indicator":"major"}}"#.utf8), response)
    }
}
