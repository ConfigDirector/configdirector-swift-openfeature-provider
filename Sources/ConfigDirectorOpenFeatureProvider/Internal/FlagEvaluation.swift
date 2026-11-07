import ConfigDirector
import OpenFeature

struct FlagEvaluation<FlagValue> {
    let key: String
    let value: FlagValue
    let variant: String?
    let reason: EvaluationReason

    func mapValue<Mapped>(_ transform: (FlagValue) -> Mapped) -> FlagEvaluation<Mapped> {
        FlagEvaluation<Mapped>(key: key, value: transform(value), variant: variant, reason: reason)
    }

    func providerEvaluation() throws -> ProviderEvaluation<FlagValue> {
        switch reason {
        case .foundMatch:
            ProviderEvaluation(value: value, variant: variant, reason: "TARGETING_MATCH")
        case .rolloutSkippedNoIdentifier:
            ProviderEvaluation(value: value, variant: variant, reason: "DEFAULT")
        case .cached:
            ProviderEvaluation(value: value, variant: variant, reason: "CACHED")
        case .valueMissing:
            ProviderEvaluation(value: value, reason: "DEFAULT")
        case .configStateMissing:
            throw OpenFeatureError.flagNotFoundError(key: key)
        case .clientNotReady:
            throw OpenFeatureError.providerNotReadyError
        case .typeMismatch, .invalidNumber, .invalidJSON, .invalidBoolean:
            throw OpenFeatureError.typeMismatchError
        }
    }
}

extension FlagEvaluation {
    init(_ read: (value: FlagValue, evaluation: ConfigEvaluation)) {
        self.init(
            key: read.evaluation.key,
            value: read.value,
            variant: read.evaluation.variation?.name ?? read.evaluation.valueID,
            reason: read.evaluation.reason
        )
    }
}

extension FlagEvaluation where FlagValue == JSONValue {
    func objectFlagEvaluation(
        inCodeDefaultValue: Value,
        inCodeDefaultJSON: JSONValue
    ) -> FlagEvaluation<Value> {
        let servesTheInCodeDefaultValue = value == inCodeDefaultJSON
        return mapValue { servesTheInCodeDefaultValue ? inCodeDefaultValue : $0.openFeatureValue }
    }
}
