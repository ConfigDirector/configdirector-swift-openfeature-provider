import ConfigDirector
@testable import ConfigDirectorOpenFeatureProvider

final class FakeClient: FlagClient {
    private struct State {
        var isReady = false
        var scriptedReadiness: [Bool] = []
        var becomesReadyOnConnect = true
        var scriptedConnectionsBecomingReady: [Bool] = []
        var isConnecting = false
        var queuedConnections: [CheckedContinuation<Void, Never>] = []
        var isHoldingConnections = false
        var heldConnections: [CheckedContinuation<Void, Never>] = []
        var initializedContexts: [ConfigDirectorContext?] = []
        var updatedContexts: [ConfigDirectorContext] = []
        var closeCount = 0
    }

    private let state = Locked(State())
    private let stream: AsyncStream<ClientEvent>
    private let continuation: AsyncStream<ClientEvent>.Continuation

    init() {
        (stream, continuation) = AsyncStream<ClientEvent>.makeStream()
    }

    var isReady: Bool {
        state.withLock { state in
            state.scriptedReadiness.isEmpty ? state.isReady : state.scriptedReadiness.removeFirst()
        }
    }

    var events: AsyncStream<ClientEvent> {
        stream
    }

    var initializedContexts: [ConfigDirectorContext?] {
        state.withLock(\.initializedContexts)
    }

    var updatedContexts: [ConfigDirectorContext] {
        state.withLock(\.updatedContexts)
    }

    var closeCount: Int {
        state.withLock(\.closeCount)
    }

    func failConnections() {
        state.withLock { $0.becomesReadyOnConnect = false }
    }

    func succeedConnections() {
        state.withLock { $0.becomesReadyOnConnect = true }
    }

    func holdConnections() {
        state.withLock { $0.isHoldingConnections = true }
    }

    func releaseConnections() {
        let held = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isHoldingConnections = false
            defer { state.heldConnections = [] }
            return state.heldConnections
        }
        held.forEach { $0.resume() }
    }

    func scriptReadiness(_ answers: [Bool]) {
        state.withLock { $0.scriptedReadiness = answers }
    }

    func scriptConnections(becomingReady outcomes: [Bool]) {
        state.withLock { $0.scriptedConnectionsBecomingReady = outcomes }
    }

    func becomeReady(_ reason: ConnectReason) {
        state.withLock { $0.isReady = true }
        continuation.yield(.ready(reason))
    }

    func deliverLateReadyEvent(_ reason: ConnectReason) {
        continuation.yield(.ready(reason))
    }

    func loadCachedValues() {
        continuation.yield(.cachedValuesLoaded)
    }

    func receiveConfigs(_ keys: [String], removedKeys: [String] = []) {
        continuation.yield(.configsUpdated(ConfigsUpdate(keys: keys, removedKeys: removedKeys)))
    }

    func initialize(context: ConfigDirectorContext?) async {
        state.withLock { $0.initializedContexts.append(context) }
        await connect(reason: .initialization)
    }

    func updateContext(_ context: ConfigDirectorContext) async {
        state.withLock { $0.updatedContexts.append(context) }
        await connect(reason: .contextUpdate)
    }

    func value<Value: ConfigValue>(for _: String, default defaultValue: Value) -> Value {
        defaultValue
    }

    func value<Value: Decodable & Sendable>(
        for _: String,
        as _: Value.Type,
        default defaultValue: Value
    ) -> Value {
        defaultValue
    }

    func close() {
        state.withLock { $0.closeCount += 1 }
        continuation.finish()
    }

    private func connect(reason: ConnectReason) async {
        await startConnection()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isHeld = state.withLock { state -> Bool in
                guard state.isHoldingConnections else { return false }
                state.heldConnections.append(continuation)
                return true
            }
            if !isHeld {
                continuation.resume()
            }
        }

        let becomesReady = state.withLock { state in
            state.scriptedConnectionsBecomingReady.isEmpty
                ? state.becomesReadyOnConnect
                : state.scriptedConnectionsBecomingReady.removeFirst()
        }
        if becomesReady {
            becomeReady(reason)
        }
        startNextConnection()
    }

    private func startConnection() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isQueued = state.withLock { state -> Bool in
                guard !state.isConnecting else {
                    state.queuedConnections.append(continuation)
                    return true
                }
                state.isConnecting = true
                state.isReady = false
                return false
            }
            if !isQueued {
                continuation.resume()
            }
        }
    }

    private func startNextConnection() {
        let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.queuedConnections.isEmpty else {
                state.isConnecting = false
                return nil
            }
            state.isReady = false
            return state.queuedConnections.removeFirst()
        }
        next?.resume()
    }
}
