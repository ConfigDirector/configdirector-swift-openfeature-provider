import ConfigDirector
import Foundation
import OpenFeature

extension ConfigDirectorContext {
    init(evaluationContext: (any EvaluationContext)?) {
        guard let evaluationContext else {
            self.init()
            return
        }

        let targetingKey = evaluationContext.getTargetingKey()
        let traits = evaluationContext.getValue(key: "traits")?.asStructure() ?? [:]

        self.init(
            id: targetingKey.isEmpty ? evaluationContext.getValue(key: "id")?.identifierText : targetingKey,
            name: evaluationContext.getValue(key: "name")?.identifierText,
            traits: traits.isEmpty ? nil : traits.mapValues { TraitValue(JSONValue($0)) },
            isAnonymous: evaluationContext.getValue(key: "anonymous")?.asBoolean()
        )
    }
}

private extension Value {
    var identifierText: String? {
        switch self {
        case let .string(value): value
        case let .integer(value): String(value)
        default: nil
        }
    }
}

private extension ConfigDirectorContext.TraitValue {
    init(_ json: JSONValue) {
        switch json {
        case let .bool(value): self = .bool(value)
        case let .integer(value): self = Int(exactly: value).map { .int($0) } ?? .double(Double(value))
        case let .double(value): self = .double(value)
        case let .string(value): self = .string(value)
        case let .array(values): self = .array(values.map(Self.init))
        case let .object(values): self = .dictionary(values.mapValues(Self.init))
        case .null: self = .null
        }
    }
}
