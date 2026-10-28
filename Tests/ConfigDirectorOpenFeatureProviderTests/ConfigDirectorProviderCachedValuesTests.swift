import ConfigDirector
@testable import ConfigDirectorOpenFeatureProvider
import OpenFeature
import Testing

struct ConfigDirectorProviderCachedValuesTests {
    private let client = FakeClient()

    @Test func reportsStaleWhenTheKeptValuesAreLoadedBeforeTheClientIsReady() async {
        client.holdConnections()
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        let events = EventRecorder(provider.observe())
        let initialization = provider.initialize(initialContext: nil)

        client.loadCachedValues()

        #expect(await waitUntil { provider.status == .stale })
        #expect(await events.waitFor(count: 1) == [.stale()])
        client.releaseConnections()
        await initialization.value
    }

    @Test func reportsTheCachedReasonAndTheValueIDOfAKeptValue() async {
        client.scriptEvaluations(reason: .cached, valueID: "dark-mode-on")
        let api = OpenFeatureAPI()
        await api.setProviderAndWait(provider: ConfigDirectorProvider(client: client, ownsClient: true))

        let details = api.getClient().getBooleanDetails(key: "dark-mode", defaultValue: false)

        #expect(details.reason == "CACHED")
        #expect(details.variant == "dark-mode-on")
        #expect(details.errorCode == nil)
    }

    @Test func reportsAnErrorAndThenStaleAgainWhenInitializationTimesOutWhileServingTheKeptValues() async {
        client.failConnections()
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        let events = EventRecorder(provider.observe())
        client.loadCachedValues()
        #expect(await waitUntil { provider.status == .stale })

        await provider.initialize(initialContext: nil).value

        let recorded = await events.waitFor(count: 3)
        #expect(recorded.count == 3)
        guard recorded.count == 3, case .error = recorded[1] else {
            Issue.record("Expected stale, error, stale, got \(recorded)")
            return
        }
        #expect(recorded[2] == .stale())
        #expect(provider.status == .stale)
    }

    @Test func reportsReadyOnceLiveValuesReplaceTheKeptValues() async {
        client.failConnections()
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        let events = EventRecorder(provider.observe())
        client.loadCachedValues()
        await provider.initialize(initialContext: nil).value
        #expect(await waitUntil { provider.status == .stale })

        client.becomeReady(.initialization)

        #expect(await waitUntil { provider.status == .ready })
        #expect(await events.settled().last == .ready())
    }

    @Test func ignoresKeptValuesLoadedAfterTheClientIsReady() async {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        let events = EventRecorder(provider.observe())
        await provider.initialize(initialContext: nil).value

        client.loadCachedValues()

        #expect(await events.settled() == [.ready()])
        #expect(provider.status == .ready)
    }

    @Test func reportsAnErrorWithoutStaleWhenAContextChangeCannotConnectAfterLiveValuesArrived() async {
        client.failConnections()
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        client.loadCachedValues()
        await provider.initialize(initialContext: nil).value
        client.becomeReady(.initialization)
        #expect(await waitUntil { provider.status == .ready })
        let events = EventRecorder(provider.observe())

        await provider.onContextSet(oldContext: nil, newContext: ImmutableContext(targetingKey: "user-2"))
            .value

        let recorded = await events.settled()
        guard case .error = recorded.last else {
            Issue.record("Expected the error to be the last event, got \(recorded)")
            return
        }
        #expect(recorded.contains(.stale()) == false)
        #expect(provider.status == .error)
    }

    @Test func reportsAnErrorWithoutStaleWhenLiveValuesArrivedAsAnotherConnectionStarted() async {
        client.failConnections()
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        client.loadCachedValues()
        await provider.initialize(initialContext: nil).value
        #expect(await waitUntil { provider.status == .stale })
        let events = EventRecorder(provider.observe())
        client.deliverLateReadyEvent(.initialization)
        client.receiveConfigs(["dark-mode"])
        _ = await events.waitFor(count: 2)

        await provider.onContextSet(oldContext: nil, newContext: ImmutableContext(targetingKey: "user-2"))
            .value

        let recorded = await events.settledStatusEvents()
        guard case .error = recorded.last else {
            Issue.record("Expected the error to be the last event, got \(recorded)")
            return
        }
        #expect(provider.status == .error)
    }

    @Test func reportsStaleAgainWhenAContextChangeCannotConnectWhileServingTheKeptValues() async {
        client.failConnections()
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        client.loadCachedValues()
        await provider.initialize(initialContext: nil).value
        #expect(await waitUntil { provider.status == .stale })
        let events = EventRecorder(provider.observe())

        await provider.onContextSet(oldContext: nil, newContext: ImmutableContext(targetingKey: "user-2"))
            .value

        let recorded = await events.settled()
        #expect(recorded.first == .stale(), "the status replayed to a new subscriber")
        #expect(recorded.contains(.reconciling()))
        #expect(recorded.last == .stale())
        #expect(provider.status == .stale)
    }
}
