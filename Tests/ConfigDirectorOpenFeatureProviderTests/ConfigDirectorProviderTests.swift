import ConfigDirector
@testable import ConfigDirectorOpenFeatureProvider
import OpenFeature
import Testing

struct ConfigDirectorProviderTests {
    private let client = FakeClient()

    @Test func identifiesItselfAsTheConfigDirectorProvider() {
        let provider = ConfigDirectorProvider(client: client)

        #expect(provider.metadata.name == "ConfigDirectorProvider")
    }

    @Test func rejectsABlankSDKKeyOnCreation() {
        #expect(throws: ConfigDirectorError.missingClientSDKKey) {
            try ConfigDirectorProvider(clientSDKKey: " ")
        }
    }

    @Test func isNotReadyBeforeItIsInitialized() {
        let provider = ConfigDirectorProvider(client: client)

        #expect(provider.status == .notReady)
    }

    @Test func addsNoHooks() {
        let provider = ConfigDirectorProvider(client: client)

        #expect(provider.hooks.isEmpty)
    }

    @Test func initializesTheClientWithTheMappedContext() async {
        let provider = ConfigDirectorProvider(client: client)

        await provider.initialize(initialContext: ImmutableContext(targetingKey: "user-123")).value

        #expect(client.initializedContexts == [ConfigDirectorContext(id: "user-123")])
    }

    @Test func reportsReadyOnceWhenTheClientBecomesReady() async {
        let provider = ConfigDirectorProvider(client: client)
        let events = EventRecorder(provider.observe())

        await provider.initialize(initialContext: nil).value

        #expect(await events.settled() == [.ready()])
    }

    @Test func isReadyByTheTimeInitializationCompletes() async {
        let provider = ConfigDirectorProvider(client: client)

        await provider.initialize(initialContext: nil).value

        #expect(provider.status == .ready)
    }

    @Test func reportsAnErrorWhenTheClientDoesNotBecomeReadyDuringInitialization() async throws {
        client.failConnections()
        let provider = ConfigDirectorProvider(client: client)
        let events = EventRecorder(provider.observe())

        await provider.initialize(initialContext: nil).value

        #expect(provider.status == .error)
        let recorded = await events.settled()
        guard case let .error(details) = try #require(recorded.first), recorded.count == 1 else {
            Issue.record("Expected a single error event, got \(recorded)")
            return
        }
        #expect(details?.errorCode == .general)
        #expect(details?.message?.contains("did not become ready during initialization") == true)
    }

    @Test func reportsReadyOnceTheClientRecoversFromAFailedInitialization() async {
        client.failConnections()
        let provider = ConfigDirectorProvider(client: client)
        let events = EventRecorder(provider.observe())
        await provider.initialize(initialContext: nil).value

        client.becomeReady(.initialization)

        let recorded = await events.waitFor(count: 2)
        #expect(recorded.last == .ready())
        #expect(provider.status == .ready)
    }

    @Test func reportsReadyWhenTheClientRecoversWhileTheErrorIsBeingReported() async {
        client.scriptReadiness([false, true])
        client.failConnections()
        let provider = ConfigDirectorProvider(client: client)
        let events = EventRecorder(provider.observe())

        await provider.initialize(initialContext: nil).value

        let recorded = await events.waitFor(count: 2)
        #expect(recorded.last == .ready())
        #expect(provider.status == .ready)
    }

    @Test func updatesTheClientWithTheMappedNewContext() async {
        let provider = ConfigDirectorProvider(client: client)
        await provider.initialize(initialContext: ImmutableContext(targetingKey: "user-123")).value

        await provider.onContextSet(
            oldContext: ImmutableContext(targetingKey: "user-123"),
            newContext: ImmutableContext(targetingKey: "user-456")
        ).value

        #expect(client.updatedContexts == [ConfigDirectorContext(id: "user-456")])
    }

    @Test func reportsReconcilingAndThenTheContextChange() async {
        let provider = ConfigDirectorProvider(client: client)
        await provider.initialize(initialContext: nil).value
        let events = EventRecorder(provider.observe())

        await provider.onContextSet(oldContext: nil, newContext: ImmutableContext()).value

        #expect(await events.settled() == [.ready(), .reconciling(), .contextChanged()])
        #expect(provider.status == .ready)
    }

    @Test func isReconcilingWhileTheClientIsStillConnecting() async {
        let provider = ConfigDirectorProvider(client: client)
        await provider.initialize(initialContext: nil).value
        client.holdConnections()

        let change = provider.onContextSet(oldContext: nil, newContext: ImmutableContext())

        #expect(await waitUntil { provider.status == .reconciling })
        client.releaseConnections()
        await change.value
        #expect(provider.status == .ready)
    }

    @Test func reportsAnErrorWhenTheClientDoesNotBecomeReadyAfterAContextChange() async throws {
        let provider = ConfigDirectorProvider(client: client)
        await provider.initialize(initialContext: nil).value
        client.failConnections()
        let events = EventRecorder(provider.observe())

        await provider.onContextSet(oldContext: nil, newContext: ImmutableContext()).value

        #expect(provider.status == .error)
        let recorded = await events.settled()
        guard case let .error(details) = try #require(recorded.last), recorded.count == 3 else {
            Issue.record("Expected ready, reconciling and an error, got \(recorded)")
            return
        }
        #expect(details?.errorCode == .general)
        #expect(details?.message?.contains("did not become ready after the context changed") == true)
    }

    @Test func reportsReadyOnceTheClientRecoversFromAFailedContextChange() async {
        let provider = ConfigDirectorProvider(client: client)
        await provider.initialize(initialContext: nil).value
        client.failConnections()
        let events = EventRecorder(provider.observe())
        await provider.onContextSet(oldContext: nil, newContext: ImmutableContext()).value

        client.becomeReady(.contextUpdate)

        let recorded = await events.waitFor(count: 4)
        #expect(recorded.last == .ready())
        #expect(provider.status == .ready)
    }

    @Test func stopsWaitingToRecoverOnceAContextChangeSucceeds() async {
        client.failConnections()
        let provider = ConfigDirectorProvider(client: client)
        await provider.initialize(initialContext: nil).value
        client.succeedConnections()
        let events = EventRecorder(provider.observe())

        await provider.onContextSet(oldContext: nil, newContext: ImmutableContext()).value

        #expect(await events.settled() == [.error(), .reconciling(), .contextChanged()])
    }

    @Test func doesNotReportReadyWhenTheClientReconnectsOnItsOwn() async {
        let provider = ConfigDirectorProvider(client: client)
        await provider.initialize(initialContext: nil).value
        let events = EventRecorder(provider.observe())

        client.becomeReady(.networkResume)

        #expect(await events.settled() == [.ready()])
    }

    @Test func reportsAConfigurationChangeWithTheUpdatedKeys() async {
        let provider = ConfigDirectorProvider(client: client)
        await provider.initialize(initialContext: nil).value
        let events = EventRecorder(provider.observe())

        client.receiveConfigs(["dark-mode", "theme"])

        let recorded = await events.waitFor(count: 2)
        #expect(recorded.last == .configurationChanged(
            ProviderEventDetails(flagsChanged: ["dark-mode", "theme"])
        ))
    }

    @Test func closesTheClient() {
        let provider = ConfigDirectorProvider(client: client)

        provider.close()

        #expect(client.closeCount == 1)
    }

    @Test func closesTheClientOnlyOnce() {
        let provider = ConfigDirectorProvider(client: client)

        provider.close()
        provider.close()

        #expect(client.closeCount == 1)
    }

    @Test func closesTheClientWhenItIsReleased() {
        var provider: ConfigDirectorProvider? = ConfigDirectorProvider(client: client)
        #expect(provider != nil)

        provider = nil

        #expect(client.closeCount == 1)
    }

    @Test func letsAnInitializationInFlightFinishQuietlyAfterClosing() async {
        let provider = ConfigDirectorProvider(client: client)
        let events = EventRecorder(provider.observe())
        client.holdConnections()
        let initialization = provider.initialize(initialContext: nil)
        _ = await waitUntil { client.initializedContexts.count == 1 }

        provider.close()
        client.releaseConnections()
        await initialization.value

        #expect(await events.settled().isEmpty)
        #expect(provider.status == .notReady)
    }
}
