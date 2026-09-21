@testable import ConfigDirectorOpenFeatureProvider
import Foundation
import OpenFeature
import Testing

struct OpenFeatureIntegrationTests {
    private static let servedConfigs = [
        ServedConfig("dark-mode", "boolean", "true"),
        ServedConfig("welcome-message", "string", "Hello"),
        ServedConfig("max-retries", "integer", "3"),
        ServedConfig("largest-id", "integer", "9007199254740993"),
        ServedConfig("discount-rate", "float", "0.15"),
        ServedConfig(
            "theme",
            "json",
            #"{"primaryColor":"blue","cornerRadius":8,"scale":1.5,"tags":["a",null]}"#
        ),
        ServedConfig("no-value", "string", nil),
    ]

    private let server: StubServer
    private let api = OpenFeatureAPI()

    init() async throws {
        server = try await StubServer(serving: Self.servedConfigs)
    }

    private func makeProvider() throws -> ConfigDirectorProvider {
        try ConfigDirectorProvider(
            clientSDKKey: "sdk-key",
            options: ConfigDirectorClientOptions(
                connection: ConnectionOptions(mode: .polling, timeout: 5, baseURL: server.baseURL),
                logger: ConsoleLogger(level: .off)
            )
        )
    }

    private func registerProvider(initialContext: (any EvaluationContext)? = nil) async throws -> any Client {
        try await api.setProviderAndWait(provider: makeProvider(), initialContext: initialContext)
        return api.getClient()
    }

    @Test func reportsItsOwnIdentityToTheServerInPlaceOfTheSDKIdentity() async throws {
        _ = try await registerProvider()

        let payload = try #require(server.pollingPayloads.first)
        #expect(payload.metaContext.sdkName == "swift-openfeature-client-provider")
        #expect(payload.metaContext.sdkVersion == Constants.providerVersion)
    }

    @Test func becomesTheReadyProviderOfOpenFeatureClients() async throws {
        _ = try await registerProvider()

        #expect(api.getProviderStatus() == .ready)
        #expect(api.getProviderMetadata()?.name == "ConfigDirectorProvider")
    }

    @Test func initializesAgainstTheInitialContext() async throws {
        _ = try await registerProvider(initialContext: ImmutableContext(
            targetingKey: "user-123",
            structure: ImmutableStructure(attributes: ["name": .string("Ada")])
        ))

        let payload = try #require(server.pollingPayloads.first)
        #expect(payload.givenContext.id == "user-123")
        #expect(payload.givenContext.name == "Ada")
    }

    @Test func reconcilesAContextChange() async throws {
        _ = try await registerProvider(initialContext: ImmutableContext(targetingKey: "user-123"))

        await api.setEvaluationContextAndWait(evaluationContext: ImmutableContext(targetingKey: "user-456"))

        #expect(api.getProviderStatus() == .ready)
        #expect(server.pollingPayloads.map(\.givenContext.id) == ["user-123", "user-456"])
    }

    @Test func resolvesABoolean() async throws {
        let client = try await registerProvider()

        #expect(client.getBooleanValue(key: "dark-mode", defaultValue: false) == true)
    }

    @Test func resolvesAString() async throws {
        let client = try await registerProvider()

        #expect(client.getStringValue(key: "welcome-message", defaultValue: "Hi") == "Hello")
    }

    @Test func resolvesAnInteger() async throws {
        let client = try await registerProvider()

        #expect(client.getIntegerValue(key: "max-retries", defaultValue: 1) == 3)
    }

    @Test func resolvesAnIntegerBeyondWhatADoubleCanHold() async throws {
        let client = try await registerProvider()

        #expect(client.getIntegerValue(key: "largest-id", defaultValue: 1) == 9_007_199_254_740_993)
    }

    @Test func truncatesAFloatConfigReadAsAnInteger() async throws {
        let client = try await registerProvider()

        #expect(client.getIntegerValue(key: "discount-rate", defaultValue: 1) == 0)
    }

    @Test func resolvesADouble() async throws {
        let client = try await registerProvider()

        #expect(client.getDoubleValue(key: "discount-rate", defaultValue: 0) == 0.15)
    }

    @Test func resolvesAnObject() async throws {
        let client = try await registerProvider()

        #expect(client.getObjectValue(key: "theme", defaultValue: .null) == .structure([
            "primaryColor": .string("blue"),
            "cornerRadius": .integer(8),
            "scale": .double(1.5),
            "tags": .list([.string("a"), .null]),
        ]))
    }

    @Test func resolvesToTheDefaultValueWhenThereIsNoConfig() async throws {
        let client = try await registerProvider()

        #expect(client.getStringValue(key: "missing", defaultValue: "fallback") == "fallback")
        #expect(client.getIntegerValue(key: "missing", defaultValue: 7) == 7)
    }

    @Test func resolvesToTheDefaultValueWhenTheConfigHasNoValue() async throws {
        let client = try await registerProvider()

        #expect(client.getStringValue(key: "no-value", defaultValue: "fallback") == "fallback")
    }

    @Test func resolvesToTheDefaultValueWhenTheTypeDoesNotMatch() async throws {
        let client = try await registerProvider()

        #expect(client.getBooleanValue(key: "welcome-message", defaultValue: true) == true)
        #expect(client.getIntegerValue(key: "welcome-message", defaultValue: 7) == 7)
        #expect(client.getObjectValue(key: "welcome-message", defaultValue: .null) == .null)
    }

    @Test func resolvesToTheExactDefaultObjectIncludingValuesJSONCannotHold() async throws {
        let client = try await registerProvider()
        let fallback = Value.structure(["since": .date(Date(timeIntervalSince1970: 1_700_000_000))])

        #expect(client.getObjectValue(key: "missing", defaultValue: fallback) == fallback)
    }
}
