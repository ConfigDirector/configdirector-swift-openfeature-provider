import ConfigDirector
@_spi(Testing) import ConfigDirectorOpenFeatureProvider
import ConfigDirectorTesting
import OpenFeature
import Testing

struct InjectedClientTests {
    private let api = OpenFeatureAPI()

    @Test func resolvesTheValuesOfTheTestClient() async {
        let testClient = makeTestClient(values: [
            "dark-mode": true,
            "welcome-message": "Hello",
            "max-retries": 3,
            "discount-rate": 0.15,
            "theme": ["primaryColor": "blue", "cornerRadius": 8],
        ])
        defer { testClient.client.close() }

        await api.setProviderAndWait(provider: ConfigDirectorProvider(injectedClient: testClient.client))
        let client = api.getClient()

        #expect(api.getProviderStatus() == .ready)
        #expect(client.getBooleanValue(key: "dark-mode", defaultValue: false) == true)
        #expect(client.getStringValue(key: "welcome-message", defaultValue: "Hi") == "Hello")
        #expect(client.getIntegerValue(key: "max-retries", defaultValue: 1) == 3)
        #expect(client.getDoubleValue(key: "discount-rate", defaultValue: 0) == 0.15)
        #expect(client.getObjectValue(key: "theme", defaultValue: .null) == .structure([
            "primaryColor": .string("blue"),
            "cornerRadius": .integer(8),
        ]))
        #expect(client.getStringValue(key: "missing", defaultValue: "fallback") == "fallback")
    }

    @Test func followsAValueSetOnTheTestClient() async {
        let testClient = makeTestClient(values: ["dark-mode": false])
        defer { testClient.client.close() }
        await api.setProviderAndWait(provider: ConfigDirectorProvider(injectedClient: testClient.client))
        let events = EventRecorder(api.observe())

        testClient.setValue(true, for: "dark-mode")

        #expect(api.getClient().getBooleanValue(key: "dark-mode", defaultValue: false) == true)
        let recorded = await events.waitFor(count: 2)
        #expect(recorded.last == .configurationChanged(ProviderEventDetails(flagsChanged: ["dark-mode"])))
    }

    @Test func fallsBackToTheDefaultValueOnceTheTestClientRemovesAValue() async {
        let testClient = makeTestClient(values: ["dark-mode": true])
        defer { testClient.client.close() }
        await api.setProviderAndWait(provider: ConfigDirectorProvider(injectedClient: testClient.client))

        testClient.removeValue(for: "dark-mode")

        #expect(api.getClient().getBooleanValue(key: "dark-mode", defaultValue: false) == false)
    }

    @Test func s37ClosingTheProviderLeavesTheTestClientOpen() async {
        let testClient = makeTestClient(values: ["dark-mode": false])
        defer { testClient.client.close() }
        let provider = ConfigDirectorProvider(injectedClient: testClient.client)
        await api.setProviderAndWait(provider: provider)

        provider.close()
        testClient.setValue(true, for: "dark-mode")

        #expect(testClient.client.isReady)
        #expect(testClient.client.value(for: "dark-mode", default: false) == true)
    }

    @Test func initializesTheTestClientAgainWhenItWasAlreadyInitialized() async {
        let testClient = makeTestClient(values: ["dark-mode": true])
        defer { testClient.client.close() }
        await testClient.client.initialize(context: ConfigDirectorContext(id: "user-123"))

        await api.setProviderAndWait(
            provider: ConfigDirectorProvider(injectedClient: testClient.client),
            initialContext: ImmutableContext(targetingKey: "user-456")
        )

        #expect(api.getProviderStatus() == .ready)
        #expect(testClient.contextUpdates.map(\.id) == ["user-123", "user-456"])
    }

    @Test func updatesTheTestClientContextWhenTheEvaluationContextChanges() async {
        let testClient = makeTestClient(values: ["dark-mode": true])
        defer { testClient.client.close() }
        await api.setProviderAndWait(
            provider: ConfigDirectorProvider(injectedClient: testClient.client),
            initialContext: ImmutableContext(targetingKey: "user-123")
        )

        await api.setEvaluationContextAndWait(evaluationContext: ImmutableContext(targetingKey: "user-456"))

        #expect(api.getProviderStatus() == .ready)
        #expect(testClient.contextUpdates.map(\.id) == ["user-123", "user-456"])
    }

    @Test func becomesReadyOnceAHeldInitializationCompletes() async throws {
        let testClient = makeTestClient(values: ["dark-mode": true])
        defer { testClient.client.close() }
        testClient.holdInitialization()
        let provider = ConfigDirectorProvider(injectedClient: testClient.client)

        let initialization = provider.initialize(initialContext: nil)
        #expect(await waitUntil { testClient.client.isInitializing })
        #expect(provider.status == .notReady)
        #expect(try darkMode(of: provider) == false)

        testClient.completeInitialization()
        await initialization.value

        #expect(provider.status == .ready)
        #expect(try darkMode(of: provider) == true)
    }

    @Test func reportsAnErrorWhenAHeldInitializationTimesOut() async {
        let testClient = makeTestClient(
            values: ["dark-mode": true],
            timeout: 0.2,
            logger: ConsoleLogger(level: .off)
        )
        defer { testClient.client.close() }
        testClient.holdInitialization()

        await api.setProviderAndWait(provider: ConfigDirectorProvider(injectedClient: testClient.client))

        #expect(api.getProviderStatus() == .error)
        #expect(api.getClient().getBooleanValue(key: "dark-mode", defaultValue: false) == false)
    }

    @Test func reportsAnErrorWhenInitializationFails() async {
        let testClient = makeTestClient(values: ["dark-mode": true], logger: ConsoleLogger(level: .off))
        defer { testClient.client.close() }
        testClient.failInitialization()

        await api.setProviderAndWait(provider: ConfigDirectorProvider(injectedClient: testClient.client))

        #expect(api.getProviderStatus() == .error)
        #expect(api.getClient().getBooleanValue(key: "dark-mode", defaultValue: false) == false)
    }
}

private func darkMode(of provider: ConfigDirectorProvider) throws -> Bool {
    try provider.getBooleanEvaluation(key: "dark-mode", defaultValue: false, context: nil).value
}
