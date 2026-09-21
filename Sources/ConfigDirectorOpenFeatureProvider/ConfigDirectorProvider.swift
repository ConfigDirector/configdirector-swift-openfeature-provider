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
/// config state it holds locally, so resolving a flag never waits on the network.
///
/// ## Evaluation context
///
/// The OpenFeature evaluation context is sent to ConfigDirector as the user's context, and targeting
/// rules are evaluated against it:
///
/// | OpenFeature                        | ConfigDirector |
/// | ---------------------------------- | -------------- |
/// | the targeting key, or else `id`    | `id`           |
/// | `name`                             | `name`         |
/// | `traits`, a structure              | `traits`       |
/// | `anonymous`, a boolean             | `anonymous`    |
///
/// Any other attribute is ignored. Put the values targeting rules depend on inside `traits`.
///
/// ## Provider status
///
/// The provider is ready once ConfigDirector has delivered config state. When that does not happen
/// within `ConnectionOptions.timeout`, the provider reports an error. The underlying client keeps
/// trying to connect, and the provider reports ready as soon as it succeeds. Until then flags
/// resolve to the config state received earlier, or to their default values when there is none.
///
/// A configuration-changed event is emitted every time config state arrives, carrying the keys of
/// the configs in the update.
///
/// The OpenFeature Swift SDK does not shut providers down, so the connection stays open until the
/// provider is released or ``close()`` is called. An instance serves a single registration: after
/// closing it, create a new one.
public final class ConfigDirectorProvider: FeatureProvider, Sendable {
    private struct State {
        var isAwaitingRecovery = false
        var isClosed = false
        var listener: Task<Void, Never>?
    }

    private let client: any FlagClient
    private let statusTracker = ProviderStatusTracker()
    private let state = Locked(State())

    /// Creates a provider for `clientSDKKey`, the client SDK key from the ConfigDirector dashboard.
    ///
    /// `options` configures the underlying ConfigDirector client: application metadata, the
    /// connection mode and timeout, and logging.
    ///
    /// - Throws: `ConfigDirectorError.missingClientSDKKey` when the key is blank, and
    ///   `ConfigDirectorError.invalidBaseURL(_:)` when `ConnectionOptions.baseURL` is not absolute.
    public convenience init(
        clientSDKKey: String,
        options: ConfigDirectorClientOptions = ConfigDirectorClientOptions()
    ) throws(ConfigDirectorError) {
        try self.init(client: ConfigDirectorClient(
            clientSDKKey: clientSDKKey,
            options: options,
            identity: .openFeatureProvider(version: Constants.providerVersion)
        ))
    }

    init(client: any FlagClient) {
        self.client = client

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

        return lifecycle { [self] in
            state.withLock { $0.isAwaitingRecovery = false }
            await client.initialize(context: context)
            reportOutcome(
                success: .ready(),
                failureMessage: """
                ConfigDirector did not become ready during initialization. Flags resolve to their \
                default values until the connection succeeds.
                """
            )
        }
    }

    public func onContextSet(
        oldContext _: (any EvaluationContext)?,
        newContext: any EvaluationContext
    ) -> Future<Void, Never> {
        let context = ConfigDirectorContext(evaluationContext: newContext)

        return lifecycle { [self] in
            state.withLock { $0.isAwaitingRecovery = false }
            send(.reconciling())
            await client.updateContext(context)
            reportOutcome(
                success: .contextChanged(),
                failureMessage: """
                ConfigDirector did not become ready after the context changed. Flags resolve against \
                the previous context until the connection succeeds.
                """
            )
        }
    }

    public func getBooleanEvaluation(
        key: String,
        defaultValue: Bool,
        context _: (any EvaluationContext)?
    ) throws -> ProviderEvaluation<Bool> {
        ProviderEvaluation(value: client.value(for: key, default: defaultValue))
    }

    public func getStringEvaluation(
        key: String,
        defaultValue: String,
        context _: (any EvaluationContext)?
    ) throws -> ProviderEvaluation<String> {
        ProviderEvaluation(value: client.value(for: key, default: defaultValue))
    }

    public func getIntegerEvaluation(
        key: String,
        defaultValue: Int64,
        context _: (any EvaluationContext)?
    ) throws -> ProviderEvaluation<Int64> {
        ProviderEvaluation(value: client.value(for: key, default: Int64ConfigValue(defaultValue)).rawValue)
    }

    public func getDoubleEvaluation(
        key: String,
        defaultValue: Double,
        context _: (any EvaluationContext)?
    ) throws -> ProviderEvaluation<Double> {
        ProviderEvaluation(value: client.value(for: key, default: defaultValue))
    }

    public func getObjectEvaluation(
        key: String,
        defaultValue: Value,
        context _: (any EvaluationContext)?
    ) throws -> ProviderEvaluation<Value> {
        let fallback = JSONValue(defaultValue)
        let resolved = client.value(for: key, as: JSONValue.self, default: fallback)
        return ProviderEvaluation(value: resolved == fallback ? defaultValue : resolved.openFeatureValue)
    }

    /// Closes the connection to ConfigDirector and stops emitting provider events.
    ///
    /// The provider closes itself when it is released, so calling this is only necessary to shut it
    /// down while a reference to it is still held, for instance after
    /// `OpenFeatureAPI.shared.clearProvider()`. The provider cannot be used afterwards.
    public func close() {
        let listener = state.withLock { state -> Task<Void, Never>? in
            guard !state.isClosed else { return nil }
            state.isClosed = true
            return state.listener
        }

        guard let listener else { return }
        listener.cancel()
        client.close()
    }

    private func lifecycle(_ work: @escaping @Sendable () async -> Void) -> Future<Void, Never> {
        Future { promise in
            nonisolated(unsafe) let promise = promise
            Task {
                await work()
                promise(.success(()))
            }
        }
    }

    private func reportOutcome(success: ProviderEvent, failureMessage: String) {
        if client.isReady {
            send(success)
            return
        }

        state.withLock { $0.isAwaitingRecovery = true }
        send(.error(ProviderEventDetails(message: failureMessage, errorCode: .general)))

        if client.isReady {
            recover()
        }
    }

    private func handle(_ event: ClientEvent) {
        switch event {
        case .ready:
            recover()
        case let .configsUpdated(keys):
            send(.configurationChanged(ProviderEventDetails(flagsChanged: keys)))
        case .contextUpdated:
            break
        }
    }

    private func recover() {
        let wasAwaitingRecovery = state.withLock { state -> Bool in
            defer { state.isAwaitingRecovery = false }
            return state.isAwaitingRecovery
        }

        guard wasAwaitingRecovery else { return }
        send(.ready())
    }

    private func send(_ event: ProviderEvent) {
        guard !state.withLock(\.isClosed) else { return }
        statusTracker.send(event)
    }
}

private struct ConfigDirectorProviderMetadata: ProviderMetadata {
    let name: String? = Constants.providerName
}
