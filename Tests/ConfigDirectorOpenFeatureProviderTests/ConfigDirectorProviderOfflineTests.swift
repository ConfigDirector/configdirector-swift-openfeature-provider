import ConfigDirectorOpenFeatureProvider
import Foundation
import OpenFeature
import Testing

struct ConfigDirectorProviderOfflineTests {
    private static let offlineValues: [String: ServedValue] = [
        "dark-mode": true,
        "welcome-message": "Hello",
        "max-retries": 3,
        "discount-rate": 0.15,
        "theme": ["primaryColor": "blue", "tags": ["a", "b"]],
    ]

    private let api = OpenFeatureAPI()

    private func offlineOptions(values: [String: ServedValue]?) -> ConfigDirectorClientOptions {
        ConfigDirectorClientOptions(
            connection: ConnectionOptions(mode: .offline, values: values),
            caching: CachingOptions(enabled: false),
            logger: ConsoleLogger(level: .off)
        )
    }

    private func register(_ provider: ConfigDirectorProvider) async -> any Client {
        await api.setProviderAndWait(
            provider: provider,
            initialContext: ImmutableContext(targetingKey: "user-123")
        )
        return api.getClient()
    }

    @Test func resolvesTheOfflineValuesWithoutAClientSDKKey() async throws {
        let provider = try ConfigDirectorProvider(options: offlineOptions(values: Self.offlineValues))

        let client = await register(provider)

        #expect(client.getBooleanValue(key: "dark-mode", defaultValue: false) == true)
        #expect(client.getStringValue(key: "welcome-message", defaultValue: "Hi") == "Hello")
        #expect(client.getIntegerValue(key: "max-retries", defaultValue: 1) == 3)
        #expect(client.getDoubleValue(key: "discount-rate", defaultValue: 0) == 0.15)
        #expect(client.getObjectValue(key: "theme", defaultValue: .null) == .structure([
            "primaryColor": .string("blue"),
            "tags": .list([.string("a"), .string("b")]),
        ]))
    }

    @Test func isReadyWithASingleReadyEventOnceRegistered() async throws {
        let provider = try ConfigDirectorProvider(options: offlineOptions(values: Self.offlineValues))
        let events = EventRecorder(provider.observe())

        _ = await register(provider)

        #expect(await events.settledStatusEvents() == [.ready()])
        #expect(api.getProviderStatus() == .ready)
    }

    @Test func resolvesEveryFlagToItsInCodeDefaultValueWhenGivenNoValues() async throws {
        let provider = try ConfigDirectorProvider(options: offlineOptions(values: nil))

        let client = await register(provider)

        #expect(api.getProviderStatus() == .ready)
        #expect(client.getBooleanValue(key: "dark-mode", defaultValue: true) == true)
        #expect(client.getStringValue(key: "welcome-message", defaultValue: "Hi") == "Hi")
    }

    @Test func sendsNoRequestToConfigDirector() async throws {
        let server = try await StubServer(serving: [ServedConfig("dark-mode", "boolean", "false")])
        var options = offlineOptions(values: Self.offlineValues)
        options.connection.baseURL = server.baseURL
        let provider = try ConfigDirectorProvider(options: options)

        let client = await register(provider)
        _ = client.getBooleanValue(key: "dark-mode", defaultValue: false)
        await api.setEvaluationContextAndWait(evaluationContext: ImmutableContext(targetingKey: "user-456"))
        provider.close()

        _ = await waitUntil(timeout: 0.5) { !server.requestPaths.isEmpty }
        #expect(server.requestPaths == [])
    }

    @Test func acceptsABlankClientSDKKey() async throws {
        let provider = try ConfigDirectorProvider(
            clientSDKKey: "",
            options: offlineOptions(values: Self.offlineValues)
        )

        let client = await register(provider)

        #expect(client.getBooleanValue(key: "dark-mode", defaultValue: false) == true)
    }

    @Test func stillRequiresAClientSDKKeyOutsideOfflineMode() {
        #expect(throws: ConfigDirectorError.missingClientSDKKey) {
            try ConfigDirectorProvider(options: ConfigDirectorClientOptions())
        }
    }

    @Test func rejectsAnOfflineValueThatCannotBeServed() {
        #expect(throws: ConfigDirectorError.invalidOfflineValue(key: "discount-rate")) {
            try ConfigDirectorProvider(options: offlineOptions(values: ["discount-rate": .float(.nan)]))
        }
    }

    @Test func rejectsValuesOutsideOfflineMode() {
        #expect(throws: ConfigDirectorError.valuesRequireOfflineMode) {
            try ConfigDirectorProvider(
                clientSDKKey: "sdk-key",
                options: ConfigDirectorClientOptions(
                    connection: ConnectionOptions(values: Self.offlineValues)
                )
            )
        }
    }
}
