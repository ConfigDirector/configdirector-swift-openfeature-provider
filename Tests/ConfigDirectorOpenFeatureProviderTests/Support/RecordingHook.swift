@testable import ConfigDirectorOpenFeatureProvider
import OpenFeature

final class RecordingHook<Value: AllowedFlagValueType>: Hook, Sendable {
    typealias HookValue = Value

    private struct State {
        var afterDetails: [FlagEvaluationDetails<Value>] = []
        var errors: [OpenFeatureError] = []
        var finallyDetails: [FlagEvaluationDetails<Value>] = []
    }

    private let state = Locked(State())

    var afterDetails: [FlagEvaluationDetails<Value>] {
        state.withLock(\.afterDetails)
    }

    var errors: [OpenFeatureError] {
        state.withLock(\.errors)
    }

    var finallyDetails: [FlagEvaluationDetails<Value>] {
        state.withLock(\.finallyDetails)
    }

    func after<HookValue>(
        ctx _: HookContext<HookValue>,
        details: FlagEvaluationDetails<HookValue>,
        hints _: [String: Any]
    ) {
        guard let details = details as? FlagEvaluationDetails<Value> else { return }
        state.withLock { $0.afterDetails.append(details) }
    }

    func error(ctx _: HookContext<some Any>, error: any Error, hints _: [String: Any]) {
        guard let error = error as? OpenFeatureError else { return }
        state.withLock { $0.errors.append(error) }
    }

    func finally<HookValue>(
        ctx _: HookContext<HookValue>,
        details: FlagEvaluationDetails<HookValue>,
        hints _: [String: Any]
    ) {
        guard let details = details as? FlagEvaluationDetails<Value> else { return }
        state.withLock { $0.finallyDetails.append(details) }
    }
}
