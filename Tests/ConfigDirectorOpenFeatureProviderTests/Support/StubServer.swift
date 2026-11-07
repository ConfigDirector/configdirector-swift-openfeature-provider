@testable import ConfigDirectorOpenFeatureProvider
import Foundation
import Network

final class StubServer: Sendable {
    struct Request: Sendable {
        var path: String
        var body: Data
    }

    enum StartError: Error {
        case failed
    }

    let baseURL: URL

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.configdirector.tests.stub-server")
    private let requests = Locked<[Request]>([])
    private let configSet: Locked<String>

    init(serving configs: [ServedConfig]) async throws {
        configSet = Locked(configSetJSON(configs))
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        let requests = requests
        let configSet = configSet
        let queue = queue
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            Self.receive(on: connection, buffered: Data()) { request in
                requests.withLock { $0.append(request) }
                return request.path.hasSuffix("/client/polling/v1") ? configSet.withLock { $0 } : "{}"
            }
        }

        let hasResumed = Locked(false)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            listener.stateUpdateHandler = { state in
                let outcome: Result<Void, any Error>? = switch state {
                case .ready: .success(())
                case .failed, .cancelled: .failure(StartError.failed)
                default: nil
                }
                guard let outcome else { return }

                let shouldResume = hasResumed.withLock { resumed -> Bool in
                    defer { resumed = true }
                    return !resumed
                }
                if shouldResume {
                    continuation.resume(with: outcome)
                }
            }
            listener.start(queue: queue)
        }

        guard let port = listener.port else { throw StartError.failed }
        baseURL = URL(string: "http://127.0.0.1:\(port.rawValue)/")!
    }

    deinit {
        listener.cancel()
    }

    var requestPaths: [String] {
        requests.withLock { $0 }.map(\.path)
    }

    var pollingPayloads: [ReceivedPayload] {
        requests.withLock { $0 }
            .filter { $0.path.hasSuffix("/client/polling/v1") }
            .compactMap { try? JSONDecoder().decode(ReceivedPayload.self, from: $0.body) }
    }

    func reportedEvaluations(of key: String) -> [ReceivedEvaluation] {
        receivedTelemetry
            .flatMap(\.aggregatedEvents.evaluatedConfig)
            .map(\.event)
            .filter { $0.key == key }
    }

    var telemetryBodies: [String] {
        telemetryRequestBodies.compactMap { String(bytes: $0, encoding: .utf8) }
    }

    var reportedTrackedEvents: [ReceivedTrackedEvent] {
        receivedTelemetry.flatMap(\.discreteEvents.trackedEvents)
    }

    private var telemetryRequestBodies: [Data] {
        requests.withLock { $0 }
            .filter { $0.path.hasSuffix("/client/telemetry/v1") }
            .map(\.body)
    }

    private var receivedTelemetry: [ReceivedTelemetry] {
        telemetryRequestBodies.compactMap { try? JSONDecoder().decode(ReceivedTelemetry.self, from: $0) }
    }

    private static func receive(
        on connection: NWConnection,
        buffered: Data,
        respond: @escaping @Sendable (Request) -> String
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            let buffered = buffered + (data ?? Data())

            if let request = parse(buffered) {
                send(respond(request), on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffered: buffered, respond: respond)
            }
        }
    }

    private static func parse(_ buffered: Data) -> Request? {
        let separator = Data("\r\n\r\n".utf8)
        guard
            let headerEnd = buffered.range(of: separator),
            let head = String(bytes: buffered[..<headerEnd.lowerBound], encoding: .utf8)
        else { return nil }

        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }

        let contentLength = lines
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        let body = buffered[headerEnd.upperBound...]
        guard body.count >= contentLength else { return nil }

        return Request(path: String(requestLine[1]), body: Data(body.prefix(contentLength)))
    }

    private static func send(_ body: String, on connection: NWConnection) {
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

struct ReceivedPayload: Decodable, Sendable {
    var givenContext: ReceivedContext
    var metaContext: ReceivedMetaContext
}

struct ReceivedContext: Decodable, Equatable, Sendable {
    var id: String?
    var kind: String?
    var name: String?
}

struct ReceivedMetaContext: Decodable, Sendable {
    var sdkName: String
    var sdkVersion: String
}

struct ReceivedEvaluation: Decodable, Sendable {
    struct Value: Decodable, Sendable {
        var valueId: String?
    }

    var key: String
    var requestedType: String
    var defaultValue: Value
    var usedDefault: Bool
    var evaluationReason: String
    var ruleId: String?
    var shareId: String?
    var variationId: String?
}

struct ReceivedTrackedEvent: Decodable, Sendable {
    var name: String
    var contextKind: String?
    var contextIdentifier: String?
}

private struct ReceivedTelemetry: Decodable {
    struct DiscreteEvents: Decodable {
        var trackedEvents: [ReceivedTrackedEvent]
    }

    struct AggregatedEvents: Decodable {
        var evaluatedConfig: [AggregatedEvaluation]
    }

    struct AggregatedEvaluation: Decodable {
        var event: ReceivedEvaluation
    }

    var discreteEvents: DiscreteEvents
    var aggregatedEvents: AggregatedEvents
}

struct ServedVariation: Encodable, Sendable {
    var id: String
    var name: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
    }
}

struct ServedConfig: Sendable {
    var key: String
    var type: String
    var value: String?
    var variation: ServedVariation?
    var ruleID: String?
    var shareID: String?

    init(
        _ key: String,
        _ type: String,
        _ value: String?,
        variation: ServedVariation? = nil,
        ruleID: String? = nil,
        shareID: String? = nil
    ) {
        self.key = key
        self.type = type
        self.value = value
        self.variation = variation
        self.ruleID = ruleID
        self.shareID = shareID
    }
}

private struct ServedConfigSet: Encodable {
    struct Config: Encodable {
        var id: String
        var key: String
        var type: String
        var value: String?
        var valueId: String?
        var variation: ServedVariation?
        var ruleId: String?
        var shareId: String?
    }

    var environmentId = "env"
    var projectId = "proj"
    var kind = "full"
    var configs: [String: Config]
}

private func configSetJSON(_ configs: [ServedConfig]) -> String {
    let encoded = try? JSONEncoder().encode(ServedConfigSet(
        configs: Dictionary(uniqueKeysWithValues: configs.map { config in
            (config.key, ServedConfigSet.Config(
                id: config.key,
                key: config.key,
                type: config.type,
                value: config.value,
                valueId: "\(config.key)-value",
                variation: config.variation,
                ruleId: config.ruleID,
                shareId: config.shareID
            ))
        })
    ))

    return encoded.flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
}
