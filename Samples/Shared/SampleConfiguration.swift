import ConfigDirectorOpenFeatureProvider
import Foundation
import OpenFeature

enum SampleConfiguration {
    static func makeProvider() -> ConfigDirectorProvider? {
        guard let clientSDKKey = infoValue(for: "ConfigDirectorSDKKey") else { return nil }

        return try? ConfigDirectorProvider(
            clientSDKKey: clientSDKKey,
            options: ConfigDirectorClientOptions(logger: ConsoleLogger(level: .debug))
        )
    }

    static var context: ImmutableContext {
        var attributes: [String: Value] = [:]
        attributes["name"] = infoValue(for: "ConfigDirectorUserName").map(Value.string)
        attributes["traits"] = infoValue(for: "ConfigDirectorUserRole")
            .map { .structure(["role": .string($0)]) }

        return ImmutableContext(
            targetingKey: infoValue(for: "ConfigDirectorUserID") ?? "",
            structure: ImmutableStructure(attributes: attributes)
        )
    }

    private static func infoValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

enum SampleUser: String, CaseIterable, Identifiable {
    case configured
    case betaTester
    case anonymous

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .configured: "Configured"
        case .betaTester: "Beta tester"
        case .anonymous: "Anonymous"
        }
    }

    var context: ImmutableContext {
        switch self {
        case .configured:
            SampleConfiguration.context
        case .betaTester:
            ImmutableContext(
                targetingKey: "beta-tester",
                structure: ImmutableStructure(attributes: [
                    "name": .string("Beta Tester"),
                    "traits": .structure(["role": .string("beta")]),
                ])
            )
        case .anonymous:
            ImmutableContext(attributes: ["anonymous": .boolean(true)])
        }
    }
}
