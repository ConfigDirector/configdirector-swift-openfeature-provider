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

    var pollingPayloads: [ReceivedPayload] {
        requests.withLock { $0 }
            .filter { $0.path.hasSuffix("/client/polling/v1") }
            .compactMap { try? JSONDecoder().decode(ReceivedPayload.self, from: $0.body) }
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
        guard let headerEnd = buffered.range(of: separator) else { return nil }

        guard let head = String(bytes: buffered[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
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

struct ReceivedContext: Decodable, Sendable {
    var id: String?
    var name: String?
}

struct ReceivedMetaContext: Decodable, Sendable {
    var sdkName: String
    var sdkVersion: String
}

struct ServedConfig: Sendable {
    var key: String
    var type: String
    var value: String?

    init(_ key: String, _ type: String, _ value: String?) {
        self.key = key
        self.type = type
        self.value = value
    }
}

private struct ServedConfigSet: Encodable {
    struct Config: Encodable {
        var id: String
        var key: String
        var type: String
        var value: String?
        var valueId: String?
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
                valueId: "\(config.key)-value"
            ))
        })
    ))

    return encoded.flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
}
