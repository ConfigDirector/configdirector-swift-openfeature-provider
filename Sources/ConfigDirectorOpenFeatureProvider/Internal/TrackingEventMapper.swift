import ConfigDirector
import OpenFeature

extension TrackOptions {
    init(trackingEventDetails details: (any TrackingEventDetails)?) {
        let attributes = details?.asMap() ?? [:]

        self.init(
            value: details?.getValue().map { .double($0) },
            details: attributes.isEmpty ? nil : attributes.mapValues(\.trackedEventDetailValue)
        )
    }
}

private extension Value {
    var trackedEventDetailValue: TrackedEventDetailValue {
        switch self {
        case let .boolean(value): .bool(value)
        case let .string(value): .string(value)
        case let .integer(value): Int(exactly: value).map { .int($0) } ?? .double(Double(value))
        case let .double(value): .double(value)
        case let .date(value): .date(value)
        case let .list(values): .array(values.map(\.trackedEventDetailValue))
        case let .structure(values): .dictionary(values.mapValues(\.trackedEventDetailValue))
        case .null: .null
        }
    }
}
