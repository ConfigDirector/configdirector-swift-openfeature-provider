import Foundation
import OpenFeature

enum JSONValue: Sendable, Equatable {
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
    case null
}

extension JSONValue {
    init(_ value: Value) {
        switch value {
        case let .boolean(value): self = .bool(value)
        case let .string(value): self = .string(value)
        case let .integer(value): self = .integer(value)
        case let .double(value): self = .double(value)
        case let .date(value): self = .string(value.ISO8601Format(.init(includingFractionalSeconds: true)))
        case let .list(values): self = .array(values.map(JSONValue.init))
        case let .structure(values): self = .object(values.mapValues(JSONValue.init))
        case .null: self = .null
        }
    }

    var openFeatureValue: Value {
        switch self {
        case let .bool(value): .boolean(value)
        case let .integer(value): .integer(value)
        case let .double(value): .double(value)
        case let .string(value): .string(value)
        case let .array(values): .list(values.map(\.openFeatureValue))
        case let .object(values): .structure(values.mapValues(\.openFeatureValue))
        case .null: .null
        }
    }
}

extension JSONValue: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let values = try? container.decode([JSONValue].self) {
            self = .array(values)
        } else {
            self = try .object(container.decode([String: JSONValue].self))
        }
    }
}

extension JSONValue: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .double(value) where value.isFinite: try container.encode(value)
        case .double, .null: try container.encodeNil()
        case let .string(value): try container.encode(value)
        case let .array(values): try container.encode(values)
        case let .object(values): try container.encode(values)
        }
    }
}

extension JSONValue: CustomStringConvertible {
    var description: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let encoded = try? encoder.encode(self) else { return "null" }
        return String(bytes: encoded, encoding: .utf8) ?? "null"
    }
}
