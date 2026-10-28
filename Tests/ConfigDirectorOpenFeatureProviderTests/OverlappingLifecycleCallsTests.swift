import ConfigDirector
@testable import ConfigDirectorOpenFeatureProvider
import OpenFeature
import Testing

struct OverlappingLifecycleCallsTests {
    private let client = FakeClient()

    @Test func reportsOnlyTheLastOfTwoOverlappingContextChanges() async {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        await provider.initialize(initialContext: ImmutableContext(targetingKey: "user-1")).value
        let events = EventRecorder(provider.observe())
        client.holdConnections()

        let firstChange = provider.onContextSet(
            oldContext: ImmutableContext(targetingKey: "user-1"),
            newContext: ImmutableContext(targetingKey: "user-2")
        )
        let lastChange = provider.onContextSet(
            oldContext: ImmutableContext(targetingKey: "user-2"),
            newContext: ImmutableContext(targetingKey: "user-3")
        )
        _ = await events.waitFor(count: 3)
        client.releaseConnections()
        await firstChange.value
        await lastChange.value

        let recorded = await events.settled()
        #expect(recorded == [.ready(), .reconciling(), .reconciling(), .contextChanged()])
        #expect(provider.status == .ready)
    }

    @Test func reportsReadyAndThenTheContextChangeWhenAContextChangeOvertakesInitialization() async {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        let events = EventRecorder(provider.observe())
        client.holdConnections()

        let initialization = provider.initialize(initialContext: ImmutableContext(targetingKey: "user-1"))
        let change = provider.onContextSet(
            oldContext: ImmutableContext(targetingKey: "user-1"),
            newContext: ImmutableContext(targetingKey: "user-2")
        )
        _ = await events.waitFor(count: 1)
        client.releaseConnections()
        await initialization.value
        await change.value

        let recorded = await events.settled()
        #expect(recorded == [.reconciling(), .ready(), .contextChanged()])
        #expect(provider.status == .ready)
    }

    @Test func isReconcilingFromTheMomentAContextChangeOvertakesInitialization() async {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        client.holdConnections()
        let initialization = provider.initialize(initialContext: ImmutableContext(targetingKey: "user-1"))

        let change = provider.onContextSet(
            oldContext: ImmutableContext(targetingKey: "user-1"),
            newContext: ImmutableContext(targetingKey: "user-2")
        )

        #expect(provider.status == .reconciling)
        client.releaseConnections()
        await initialization.value
        await change.value
    }

    @Test func reportsAnErrorWhenAContextChangeThatOvertookInitializationDoesNotBecomeReady() async throws {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        let events = EventRecorder(provider.observe())
        client.holdConnections()
        client.scriptConnections(becomingReady: [true, false])

        let initialization = provider.initialize(initialContext: ImmutableContext(targetingKey: "user-1"))
        let change = provider.onContextSet(
            oldContext: ImmutableContext(targetingKey: "user-1"),
            newContext: ImmutableContext(targetingKey: "user-2")
        )
        _ = await events.waitFor(count: 1)
        client.releaseConnections()
        await initialization.value
        await change.value

        #expect(provider.status == .error)
        let recorded = await events.settled()
        guard case let .error(details) = try #require(recorded.last), recorded.count == 2 else {
            Issue.record("Expected reconciling and an error, got \(recorded)")
            return
        }
        #expect(details?.message?.contains("did not become ready after the context changed") == true)
    }

    @Test func updatesTheClientContextOnlyOnceInitializationHasFinished() async {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        client.holdConnections()

        let initialization = provider.initialize(initialContext: ImmutableContext(targetingKey: "user-1"))
        let change = provider.onContextSet(
            oldContext: ImmutableContext(targetingKey: "user-1"),
            newContext: ImmutableContext(targetingKey: "user-2")
        )
        _ = await waitUntil { client.initializedContexts.count == 1 }

        let isUpdatedDuringInitialization = await waitUntil(timeout: 0.1) { !client.updatedContexts.isEmpty }
        #expect(!isUpdatedDuringInitialization)

        client.releaseConnections()
        await initialization.value
        await change.value

        #expect(client.initializedContexts == [ConfigDirectorContext(id: "user-1")])
        #expect(client.updatedContexts == [ConfigDirectorContext(id: "user-2")])
    }

    @Test func reportsAnErrorWhenTheLastOfTwoOverlappingContextChangesDoesNotBecomeReady() async throws {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        await provider.initialize(initialContext: ImmutableContext(targetingKey: "user-1")).value
        let events = EventRecorder(provider.observe())
        client.holdConnections()
        client.scriptConnections(becomingReady: [true, false])

        let firstChange = provider.onContextSet(
            oldContext: ImmutableContext(targetingKey: "user-1"),
            newContext: ImmutableContext(targetingKey: "user-2")
        )
        let lastChange = provider.onContextSet(
            oldContext: ImmutableContext(targetingKey: "user-2"),
            newContext: ImmutableContext(targetingKey: "user-3")
        )
        _ = await events.waitFor(count: 3)
        client.releaseConnections()
        await firstChange.value
        await lastChange.value

        #expect(provider.status == .error)
        let recorded = await events.settled()
        guard case let .error(details) = try #require(recorded.last), recorded.count == 4 else {
            Issue.record("Expected ready, reconciling twice and an error, got \(recorded)")
            return
        }
        #expect(details?.message?.contains("did not become ready after the context changed") == true)
    }

    @Test func reportsReadyOnceTheClientRecoversFromTheLastOfTwoOverlappingContextChanges() async {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        await provider.initialize(initialContext: ImmutableContext(targetingKey: "user-1")).value
        client.holdConnections()
        client.scriptConnections(becomingReady: [true, false])
        let firstChange = provider.onContextSet(
            oldContext: ImmutableContext(targetingKey: "user-1"),
            newContext: ImmutableContext(targetingKey: "user-2")
        )
        let lastChange = provider.onContextSet(
            oldContext: ImmutableContext(targetingKey: "user-2"),
            newContext: ImmutableContext(targetingKey: "user-3")
        )
        client.releaseConnections()
        await firstChange.value
        await lastChange.value
        let events = EventRecorder(provider.observe())

        client.becomeReady(.contextUpdate)

        let recorded = await events.waitFor(count: 2)
        #expect(recorded == [.error(), .ready()])
        #expect(provider.status == .ready)
    }

    @Test func staysInErrorWhenAnEarlierConnectionReportsReadyAfterTheLastContextChangeFailed() async {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        await provider.initialize(initialContext: ImmutableContext(targetingKey: "user-1")).value
        client.failConnections()
        await provider.onContextSet(
            oldContext: ImmutableContext(targetingKey: "user-1"),
            newContext: ImmutableContext(targetingKey: "user-2")
        ).value
        let events = EventRecorder(provider.observe())

        client.deliverLateReadyEvent(.initialization)

        let recorded = await events.settled()
        #expect(recorded == [.error()])
        #expect(provider.status == .error)
    }
}
