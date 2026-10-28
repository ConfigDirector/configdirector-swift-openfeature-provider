import Combine
@_spi(ConfigDirectorWrapper) import ConfigDirector
import Foundation
import OpenFeature

/// An [OpenFeature](https://openfeature.dev) provider that resolves flags with the ConfigDirector
/// Swift client SDK.
///
/// Register one instance with the OpenFeature Swift SDK during application startup:
///
/// ```swift
/// let provider = try ConfigDirectorProvider(clientSDKKey: "YOUR-CLIENT-SDK-KEY")
/// await OpenFeatureAPI.shared.setProviderAndWait(
///     provider: provider,
///     initialContext: ImmutableContext(targetingKey: "user-123")
/// )
///
/// let client = OpenFeatureAPI.shared.getClient()
/// let darkMode = client.getBooleanValue(key: "dark-mode", defaultValue: false)
/// ```
///
/// The provider connects to ConfigDirector when it is registered and evaluates every flag from the
/// config state it holds locally, so resolving a flag never waits on the network. Created with
/// ``init(options:)`` in `ConnectionMode.offline` mode, it never connects and resolves every flag
/// from the values it was given.
///
/// ## Evaluation context
///
/// The OpenFeature evaluation context is sent to ConfigDirector as the context, and targeting rules
/// are evaluated against it:
///
/// | OpenFeature                        | ConfigDirector |
/// | ---------------------------------- | -------------- |
/// | the targeting key, or else `id`    | `id`           |
/// | `kind`                             | `kind`         |
/// | `name`                             | `name`         |
/// | `traits`, a structure              | `traits`       |
/// | `anonymous`, a boolean             | `anonymous`    |
///
/// Any other attribute is ignored. Put the values targeting rules depend on inside `traits`; a
/// `kind` inside `traits` is an ordinary trait. Leaving `kind` out means `user`, and a context with
/// an invalid `kind` is ignored as a whole: the SDK logs an error and flags resolve as if no context
/// was set.
///
/// ## Provider status
///
/// The provider is ready once ConfigDirector has delivered config state. When that does not happen
/// within `ConnectionOptions.timeout`, the provider reports an error. The underlying client keeps
/// trying to connect, and the provider reports ready as soon as it succeeds. Until then flags
/// resolve to the config state received earlier, or to their default values when there is none.
///
/// On a launch after one that received config state, the client serves the values it kept on the
/// device until live values arrive; see `ConfigDirectorClientOptions.caching`. The provider reports
/// the stale status from the moment those values are loaded, and again after the error a timeout
/// reports, until live values make the client ready.
///
/// A configuration-changed event is emitted every time config state arrives, carrying the keys of
/// the configs in the update followed by the keys of configs a full update removed.
///
/// The OpenFeature Swift SDK does not shut providers down, so the connection stays open until the
/// provider is released or ``close()`` is called. An instance serves a single registration: after
/// closing it, create a new one.
public final class ConfigDirectorProvider: FeatureProvider, Sendable {
    private struct State {
        var lifecycleReporting = LifecycleReporting()
        var latestLifecycleTask: Task<Void, Never>?
        var isAwaitingRecovery = false
        var isServingCachedValues = false
        var listener: Task<Void, Never>?
    }

    private let client: any FlagClient
    private let ownsClient: Bool
    private let statusTracker = ProviderStatusTracker()
    private let state = Locked(State())
    private let isClosed = Locked(false)

    /// Creates a provider for `clientSDKKey`, the client SDK key from the ConfigDirector dashboard.
    ///
    /// `options` configures the underlying ConfigDirector client: application metadata, the
    /// connection mode and timeout, and logging.
    ///
    /// - Throws: `ConfigDirectorError.missingClientSDKKey` when the key is blank outside
    ///   `ConnectionMode.offline` mode, `ConfigDirectorError.invalidBaseURL(_:)` when
    ///   `ConnectionOptions.baseURL` is not absolute, `ConfigDirectorError.valuesRequireOfflineMode`
    ///   when `ConnectionOptions.values` is given outside offline mode, and
    ///   `ConfigDirectorError.invalidOfflineValue(key:)` when one of those values cannot be served.
    public convenience init(
        clientSDKKey: String,
        options: ConfigDirectorClientOptions = ConfigDirectorClientOptions()
    ) throws(ConfigDirectorError) {
        try self.init(
            client: ConfigDirectorClient(
                clientSDKKey: clientSDKKey,
                options: options,
                identity: .openFeatureProvider(version: Constants.providerVersion)
            ),
            ownsClient: true
        )
    }

    /// Creates a provider in `ConnectionMode.offline` mode, which needs no client SDK key. The
    /// provider never connects to ConfigDirector and resolves every flag to its value in
    /// `ConnectionOptions.values`, the same for every evaluation context, or to its in-code default
    /// value when that value is missing or of another type. It is ready as soon as it is registered.
    ///
    /// - Throws: `ConfigDirectorError.missingClientSDKKey` when `ConnectionOptions.mode` is not
    ///   `ConnectionMode.offline`, and `ConfigDirectorError.invalidOfflineValue(key:)` when a value in
    ///   `ConnectionOptions.values` cannot be served.
    public convenience init(options: ConfigDirectorClientOptions) throws(ConfigDirectorError) {
        try self.init(
            client: ConfigDirectorClient(
                options: options,
                identity: .openFeatureProvider(version: Constants.providerVersion)
            ),
            ownsClient: true
        )
    }

    /// Creates a provider over a `ConfigDirectorClient` the caller owns, for tests: usually the
    /// `client` of a test client made with the Swift SDK's `ConfigDirectorTesting` product.
    ///
    /// The provider initializes the client when it is registered and updates its context when the
    /// evaluation context changes, as it does with a client it creates itself, so a client that was
    /// already initialized reconnects. It never closes the client: ``close()`` stops the provider
    /// and leaves the client open for the test to close.
    ///
    /// Import the module with `@_spi(Testing) import ConfigDirectorOpenFeatureProvider` to use it.
    @_spi(Testing)
    public convenience init(injectedClient client: ConfigDirectorClient) {
        self.init(client: client, ownsClient: false)
    }

    init(client: any FlagClient, ownsClient: Bool) {
        self.client = client
        self.ownsClient = ownsClient

        let events = client.events
        let listener = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
        state.withLock { $0.listener = listener }
    }

    deinit {
        close()
    }

    public var hooks: [any Hook] {
        []
    }

    public var metadata: any ProviderMetadata {
        ConfigDirectorProviderMetadata()
    }

    public var status: ProviderStatus {
        statusTracker.status
    }

    public func observe() -> AnyPublisher<ProviderEvent, Never> {
        statusTracker.observe()
    }

    public func initialize(initialContext: (any EvaluationContext)?) -> Future<Void, Never> {
        let context = ConfigDirectorContext(evaluationContext: initialContext)

        return lifecycle(.initialization) { [self] in
            await client.initialize(context: context)
        }
    }

    public func onContextSet(
        oldContext _: (any EvaluationContext)?,
        newContext: any EvaluationContext
    ) -> Future<Void, Never> {
        let context = ConfigDirectorContext(evaluationContext: newContext)

        return lifecycle(.contextUpdate) { [self] in
            await client.updateContext(context)
        }
    }

    public func getBooleanEvaluation(
        key: String,
        defaultValue: Bool,
        context _: (any EvaluationContext)?
    ) throws -> ProviderEvaluation<Bool> {
        try client.evaluateFlag(key, default: defaultValue).providerEvaluation()
    }

    public func getStringEvaluation(
        key: String,
        defaultValue: String,
        context _: (any EvaluationContext)?
    ) throws -> ProviderEvaluation<String> {
        try client.evaluateFlag(key, default: defaultValue).providerEvaluation()
    }

    public func getIntegerEvaluation(
        key: String,
        defaultValue: Int64,
        context _: (any EvaluationContext)?
    ) throws -> ProviderEvaluation<Int64> {
        try client.evaluateFlag(key, default: Int64ConfigValue(defaultValue))
            .mapValue(\.rawValue)
            .providerEvaluation()
    }

    public func getDoubleEvaluation(
        key: String,
        defaultValue: Double,
        context _: (any EvaluationContext)?
    ) throws -> ProviderEvaluation<Double> {
        try client.evaluateFlag(key, default: defaultValue).providerEvaluation()
    }

    public func getObjectEvaluation(
        key: String,
        defaultValue: Value,
        context _: (any EvaluationContext)?
    ) throws -> ProviderEvaluation<Value> {
        let inCodeDefaultJSON = JSONValue(defaultValue)
        return try client.evaluateFlag(key, as: JSONValue.self, default: inCodeDefaultJSON)
            .objectFlagEvaluation(inCodeDefaultValue: defaultValue, inCodeDefaultJSON: inCodeDefaultJSON)
            .providerEvaluation()
    }

    /// Closes the connection to ConfigDirector and stops emitting provider events.
    ///
    /// The provider closes itself when it is released, so calling this is only necessary to shut it
    /// down while a reference to it is still held, for instance after
    /// `OpenFeatureAPI.shared.clearProvider()`. The provider cannot be used afterwards. A client the
    /// provider was given through ``init(injectedClient:)`` stays open.
    public func close() {
        let wasClosed = isClosed.withLock { isClosed in
            defer { isClosed = true }
            return isClosed
        }
        guard !wasClosed else { return }

        state.withLock(\.listener)?.cancel()
        if ownsClient {
            client.close()
        }
    }

    private func lifecycle(
        _ call: LifecycleCall,
        connect: @escaping @Sendable () async -> Void
    ) -> Future<Void, Never> {
        Future { [self] promise in
            nonisolated(unsafe) let promise = promise
            state.withLock { state in
                state.isAwaitingRecovery = false
                let number = state.lifecycleReporting.numberNextCall()
                if let startEvent = call.startEvent {
                    send(startEvent)
                }

                let previousTask = state.latestLifecycleTask
                state.latestLifecycleTask = Task {
                    await previousTask?.value
                    await connect()
                    reportOutcome(of: call, numbered: number)
                    promise(.success(()))
                }
            }
        }
    }

    private func reportOutcome(of call: LifecycleCall, numbered number: Int) {
        state.withLock { state in
            let outcome = state.lifecycleReporting.outcome(
                of: call,
                numbered: number,
                isClientReady: client.isReady
            )
            switch outcome {
            case .overtakenByALaterCall:
                break
            case .ready:
                send(.ready())
            case .contextChanged:
                send(.contextChanged())
            case .readyThenContextChanged:
                send(.ready())
                send(.contextChanged())
            case .error:
                reportFailure(message: call.failureMessage, state: &state)
            }
        }
    }

    private func reportFailure(message: String, state: inout State) {
        state.isAwaitingRecovery = true
        send(.error(ProviderEventDetails(message: message, errorCode: .general)))
        switch FailureReport.decide(isServingCachedValues: state.isServingCachedValues) {
        case .errorThenStale:
            send(.stale())
        case .error:
            break
        }

        recoverIfTheClientIsReady(state: &state)
    }

    private func handle(_ event: ClientEvent) {
        switch event {
        case .ready:
            state.withLock { state in
                state.isServingCachedValues = false
                recoverIfTheClientIsReady(state: &state)
            }
        case let .configsUpdated(update):
            send(.configurationChanged(ProviderEventDetails(flagsChanged: update.keys + update.removedKeys)))
        case .cachedValuesLoaded:
            serveCachedValues()
        case .contextUpdated:
            break
        }
    }

    private func serveCachedValues() {
        state.withLock { state in
            guard !client.isReady else { return }
            state.isServingCachedValues = true
            send(.stale())
        }
    }

    private func recoverIfTheClientIsReady(state: inout State) {
        guard client.isReady else { return }

        let wasAwaitingRecovery = state.isAwaitingRecovery
        state.isAwaitingRecovery = false
        state.isServingCachedValues = false
        guard wasAwaitingRecovery else { return }
        send(.ready())
    }

    private func send(_ event: ProviderEvent) {
        guard !isClosed.withLock({ $0 }) else { return }
        statusTracker.send(event)
    }
}

private enum FailureReport {
    case error
    case errorThenStale

    static func decide(isServingCachedValues: Bool) -> FailureReport {
        isServingCachedValues ? .errorThenStale : .error
    }
}

private struct ConfigDirectorProviderMetadata: ProviderMetadata {
    let name: String? = Constants.providerName
}
