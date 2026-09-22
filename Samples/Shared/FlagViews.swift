import Combine
import Foundation
import OpenFeature
import SwiftUI

struct FlagRow: View {
    private let flagKey: String
    private let read: (any Client) -> String

    @State private var value: String

    init(_ flagKey: String, default defaultValue: Bool) {
        self.init(flagKey, defaultValue: defaultValue.description) {
            $0.getBooleanValue(key: flagKey, defaultValue: defaultValue).description
        }
    }

    init(_ flagKey: String, default defaultValue: Int64) {
        self.init(flagKey, defaultValue: defaultValue.description) {
            $0.getIntegerValue(key: flagKey, defaultValue: defaultValue).description
        }
    }

    init(_ flagKey: String, default defaultValue: String) {
        self.init(flagKey, defaultValue: defaultValue) {
            $0.getStringValue(key: flagKey, defaultValue: defaultValue)
        }
    }

    init(_ flagKey: String, default defaultValue: Value) {
        self.init(flagKey, defaultValue: defaultValue.jsonText) {
            $0.getObjectValue(key: flagKey, defaultValue: defaultValue).jsonText
        }
    }

    private init(_ flagKey: String, defaultValue: String, read: @escaping (any Client) -> String) {
        self.flagKey = flagKey
        self.read = read
        _value = State(initialValue: defaultValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(flagKey)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
        }
        .padding(.vertical, 2)
        .onReceive(ProviderEvents.onMain) { _ in
            value = read(OpenFeatureAPI.shared.getClient())
        }
    }
}

struct FlagRows: View {
    var body: some View {
        FlagRow("temporary-feature-flag", default: false)
        FlagRow("permanent-kill-switch", default: true)
        FlagRow("integer-config", default: 10)
        FlagRow("day-of-the-week-config", default: "Friday")
        FlagRow("json-value-config", default: Value.structure([:]))
    }
}

struct ProviderStatusLabel: View {
    let status: ProviderStatus

    var body: some View {
        Text(status.label)
            .foregroundColor(status == .ready ? .green : .secondary)
    }
}

struct UserPicker: View {
    @State private var selectedUser = SampleUser.configured

    var body: some View {
        Picker("User", selection: selection) {
            ForEach(SampleUser.allCases) { user in
                Text(user.label).tag(user)
            }
        }
    }

    private var selection: Binding<SampleUser> {
        Binding(
            get: { selectedUser },
            set: { user in
                selectedUser = user
                OpenFeatureAPI.shared.setEvaluationContext(evaluationContext: user.context)
            }
        )
    }
}

extension ProviderStatus {
    var label: String {
        switch self {
        case .ready: "Ready"
        case .reconciling: "Reconciling…"
        case .error, .fatal: "Error"
        case .stale: "Stale"
        case .notReady: "Connecting…"
        }
    }
}

struct ContextSummary: View {
    let context: (any EvaluationContext)?

    var body: some View {
        if let context {
            VStack(alignment: .leading, spacing: 4) {
                field("targetingKey", context.getTargetingKey())
                field("name", context.getValue(key: "name")?.asString())
                field("anonymous", context.getValue(key: "anonymous")?.asBoolean()?.description)
                field("traits", context.getValue(key: "traits")?.asStructure().map(Self.describe))
            }
            .padding(.vertical, 2)
        } else {
            Text("No context — flags are evaluated without one.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func field(_ label: String, _ value: String?) -> some View {
        let text = value.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        return Text("\(label): \(text)")
            .font(.system(.caption, design: .monospaced))
    }

    private static func describe(_ traits: [String: Value]) -> String {
        traits
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}

enum ProviderEvents {
    static var onMain: AnyPublisher<ProviderEvent, Never> {
        OpenFeatureAPI.shared.observe()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

private extension Value {
    var jsonText: String {
        let options: JSONSerialization.WritingOptions = [
            .sortedKeys,
            .fragmentsAllowed,
            .withoutEscapingSlashes,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: options),
              let text = String(bytes: data, encoding: .utf8)
        else {
            return description
        }
        return text
    }

    private var jsonObject: Any {
        switch self {
        case let .boolean(value): value
        case let .string(value): value
        case let .integer(value): value
        case let .double(value): value
        case let .date(value): value.ISO8601Format()
        case let .list(values): values.map(\.jsonObject)
        case let .structure(values): values.mapValues(\.jsonObject)
        case .null: NSNull()
        }
    }
}
