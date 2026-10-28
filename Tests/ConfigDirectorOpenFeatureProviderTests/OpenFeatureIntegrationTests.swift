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
        ServedConfig("bare-limit", "json", "42"),
        ServedConfig("regions", "json", #"["eu","us"]"#),
        ServedConfig("broken-theme", "json", "{oops"),
        ServedConfig("no-theme", "json", nil),
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
                caching: CachingOptions(enabled: false),
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

    @Test func sendsTheKindAttributeAsTheContextKind() async throws {
        _ = try await registerProvider(initialContext: ImmutableContext(
            targetingKey: "device-42",
            structure: ImmutableStructure(attributes: ["kind": .string("device")])
        ))

        let payload = try #require(server.pollingPayloads.first)
        #expect(payload.givenContext == ReceivedContext(id: "device-42", kind: "device"))
    }

    @Test func becomesReadyAndSendsNoContextWhenTheInitialContextHasAnInvalidKind() async throws {
        _ = try await registerProvider(initialContext: ImmutableContext(
            targetingKey: "device-42",
            structure: ImmutableStructure(attributes: [
                "kind": .string("Device"),
                "name": .string("Front door"),
            ])
        ))

        #expect(api.getProviderStatus() == .ready)
        #expect(server.pollingPayloads.map(\.givenContext) == [ReceivedContext()])
    }

    @Test func reconcilesAContextChange() async throws {
        _ = try await registerProvider(initialContext: ImmutableContext(targetingKey: "user-123"))

        await api.setEvaluationContextAndWait(evaluationContext: ImmutableContext(targetingKey: "user-456"))

        #expect(api.getProviderStatus() == .ready)
        #expect(server.pollingPayloads.map(\.givenContext.id) == ["user-123", "user-456"])
    }

    @Test func reportsAContextChangeAndSendsNoContextWhenTheNewContextHasAnInvalidKind() async throws {
        _ = try await registerProvider(initialContext: ImmutableContext(targetingKey: "user-123"))
        let events = EventRecorder(api.observe())

        await api.setEvaluationContextAndWait(evaluationContext: ImmutableContext(
            targetingKey: "device-42",
            structure: ImmutableStructure(attributes: [
                "kind": .string("Device"),
                "name": .string("Front door"),
            ])
        ))

        #expect(await events.settledStatusEvents() == [.ready(), .reconciling(), .contextChanged()])
        #expect(api.getProviderStatus() == .ready)
        #expect(server.pollingPayloads.map(\.givenContext) == [
            ReceivedContext(id: "user-123"),
            ReceivedContext(),
        ])
    }

    @Test func resolvesABooleanWithTheTargetingMatchReasonAndTheValueID() async throws {
        let client = try await registerProvider()

        let details = client.getBooleanDetails(key: "dark-mode", defaultValue: false)

        #expect(details.value == true)
        #expect(details.reason == "TARGETING_MATCH")
        #expect(details.variant == "dark-mode-value")
        #expect(details.errorCode == nil)
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

    @Test func resolvesToTheDefaultValueWithFlagNotFoundWhenThereIsNoConfig() async throws {
        let client = try await registerProvider()

        #expect(client.getStringValue(key: "missing", defaultValue: "fallback") == "fallback")

        let details = client.getIntegerDetails(key: "missing", defaultValue: 7)

        #expect(details.value == 7)
        #expect(details.errorCode == .flagNotFound)
        #expect(details.reason == "error")
    }

    @Test func resolvesToTheDefaultValueWithTheDefaultReasonWhenTheConfigHasNoValue() async throws {
        let client = try await registerProvider()

        let details = client.getStringDetails(key: "no-value", defaultValue: "fallback")

        #expect(details.value == "fallback")
        #expect(details.reason == "DEFAULT")
        #expect(details.variant == nil)
        #expect(details.errorCode == nil)
    }

    @Test func resolvesToTheDefaultValueWithTypeMismatchWhenAStringConfigDoesNotSpellABoolean() async throws {
        let client = try await registerProvider()

        let details = client.getBooleanDetails(key: "welcome-message", defaultValue: true)

        #expect(details.value == true)
        #expect(details.errorCode == .typeMismatch)
        #expect(details.reason == "error")
    }

    @Test func resolvesToTheDefaultValueWithTypeMismatchWhenAStringConfigDoesNotSpellANumber() async throws {
        let client = try await registerProvider()

        let details = client.getIntegerDetails(key: "welcome-message", defaultValue: 7)

        #expect(details.value == 7)
        #expect(details.errorCode == .typeMismatch)
        #expect(details.reason == "error")
    }

    @Test func resolvesToTheDefaultValueWithTypeMismatchWhenAStringConfigIsReadAsAnObject() async throws {
        let client = try await registerProvider()

        let details = client.getObjectDetails(key: "welcome-message", defaultValue: .null)

        #expect(details.value == .null)
        #expect(details.errorCode == .typeMismatch)
        #expect(details.reason == "error")
    }

    @Test func resolvesToTheDefaultValueWithTypeMismatchWhenAJSONConfigDoesNotParse() async throws {
        let client = try await registerProvider()

        let details = client.getObjectDetails(key: "broken-theme", defaultValue: .null)

        #expect(details.value == .null)
        #expect(details.errorCode == .typeMismatch)
        #expect(details.reason == "error")
    }

    @Test func resolvesAnObjectFlagToItsDefaultWithTypeMismatchWhenTheConfigHoldsANumber() async throws {
        let client = try await registerProvider()
        let fallback = Value.structure(["max": .integer(1)])

        let details = client.getObjectDetails(key: "bare-limit", defaultValue: fallback)

        #expect(details.value == fallback)
        #expect(details.errorCode == .typeMismatch)
        #expect(details.reason == "error")
    }

    @Test func resolvesAListFlagToItsDefaultWithTypeMismatchWhenTheConfigHoldsAnObject() async throws {
        let client = try await registerProvider()
        let fallback = Value.list([.string("eu")])

        let details = client.getObjectDetails(key: "theme", defaultValue: fallback)

        #expect(details.value == fallback)
        #expect(details.errorCode == .typeMismatch)
        #expect(details.reason == "error")
    }

    @Test func resolvesAnObjectFlagWithAnObjectDefaultToTheServedObject() async throws {
        let client = try await registerProvider()

        #expect(client.getObjectValue(key: "theme", defaultValue: .structure([:])) == .structure([
            "primaryColor": .string("blue"),
            "cornerRadius": .integer(8),
            "scale": .double(1.5),
            "tags": .list([.string("a"), .null]),
        ]))
    }

    @Test func resolvesAListFlagWithAListDefaultToTheServedList() async throws {
        let client = try await registerProvider()

        #expect(client.getObjectValue(key: "regions", defaultValue: .list([])) == .list([
            .string("eu"),
            .string("us"),
        ]))
    }

    @Test func resolvesToTheExactDefaultObjectIncludingValuesJSONCannotHold() async throws {
        let client = try await registerProvider()
        let fallback = Value.structure(["since": .date(Date(timeIntervalSince1970: 1_700_000_000))])

        #expect(client.getObjectValue(key: "missing", defaultValue: fallback) == fallback)
    }

    @Test func resolvesToTheExactDefaultObjectWhenTheConfigHasNoValue() async throws {
        let client = try await registerProvider()
        let fallback = Value.structure(["since": .date(Date(timeIntervalSince1970: 1_700_000_000))])

        let details = client.getObjectDetails(key: "no-theme", defaultValue: fallback)

        #expect(details.value == fallback)
        #expect(details.reason == "DEFAULT")
    }

    @Test func runsAnAfterHookWithTheTargetingMatchReasonAndTheValueID() async throws {
        let client = try await registerProvider()
        let hook = RecordingHook<Bool>()
        api.addHooks(hooks: hook)

        _ = client.getBooleanValue(key: "dark-mode", defaultValue: false)

        #expect(hook.afterDetails.count == 1)
        let details = try #require(hook.afterDetails.first)
        #expect(details.reason == "TARGETING_MATCH")
        #expect(details.variant == "dark-mode-value")
    }

    @Test func runsAnErrorHookWhenThereIsNoConfig() async throws {
        let client = try await registerProvider()
        let hook = RecordingHook<String>()
        api.addHooks(hooks: hook)

        _ = client.getStringValue(key: "missing", defaultValue: "fallback")

        #expect(hook.errors == [.flagNotFoundError(key: "missing")])
        #expect(hook.afterDetails.isEmpty)
        let details = try #require(hook.finallyDetails.first)
        #expect(details.value == "fallback")
        #expect(details.errorCode == .flagNotFound)
        #expect(details.reason == "error")
    }
}
