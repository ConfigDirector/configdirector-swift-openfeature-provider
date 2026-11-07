@testable import ConfigDirectorOpenFeatureProvider
import Foundation
import OpenFeature
import Testing

struct OpenFeatureTrackingTests {
    private let server: StubServer
    private let api = OpenFeatureAPI()
    private let provider: ConfigDirectorProvider

    init() async throws {
        server = try await StubServer(serving: [ServedConfig("dark-mode", "boolean", "true")])
        provider = try ConfigDirectorProvider(
            clientSDKKey: "sdk-key",
            options: ConfigDirectorClientOptions(
                connection: ConnectionOptions(mode: .polling, timeout: 5, baseURL: server.baseURL),
                caching: CachingOptions(enabled: false),
                logger: ConsoleLogger(level: .off)
            )
        )
        await api.setProviderAndWait(
            provider: provider,
            initialContext: ImmutableContext(targetingKey: "user-123")
        )
    }

    @Test func aTrackCallReachesConfigDirectorOnTheTelemetryReport() async throws {
        api.getClient().track(
            key: "checkout-completed",
            details: ImmutableTrackingEventDetails(
                value: 49.9,
                structure: ImmutableStructure(attributes: ["plan": .string("pro")])
            )
        )

        provider.close()
        let server = server
        #expect(await waitUntil { !server.reportedTrackedEvents.isEmpty })

        let event = try #require(server.reportedTrackedEvents.first)
        #expect(event.name == "checkout-completed")
        #expect(event.contextKind == "user")
        #expect(event.contextIdentifier == "user-123")

        let body = try #require(server.telemetryBodies.first { $0.contains("checkout-completed") })
        #expect(body.contains(#""value":49.9"#))
        #expect(body.contains(#""details":{"plan":"pro"}"#))
    }
}
