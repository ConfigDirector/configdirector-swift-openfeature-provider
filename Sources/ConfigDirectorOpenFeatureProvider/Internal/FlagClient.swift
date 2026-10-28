import ConfigDirector

protocol FlagClient: Sendable {
    var isReady: Bool { get }
    var events: AsyncStream<ClientEvent> { get }

    func initialize(context: ConfigDirectorContext?) async
    func updateContext(_ context: ConfigDirectorContext) async
    func evaluateFlag<Value: ConfigValue>(_ key: String, default defaultValue: Value) -> FlagEvaluation<Value>
    func evaluateFlag<Value: Decodable & Sendable>(
        _ key: String,
        as type: Value.Type,
        default defaultValue: Value
    ) -> FlagEvaluation<Value>
    func close()
}

extension ConfigDirectorClient: FlagClient {
    func evaluateFlag<Value: ConfigValue>(
        _ key: String,
        default defaultValue: Value
    ) -> FlagEvaluation<Value> {
        FlagEvaluation(evaluate(key, default: defaultValue))
    }

    func evaluateFlag<Value: Decodable & Sendable>(
        _ key: String,
        as type: Value.Type,
        default defaultValue: Value
    ) -> FlagEvaluation<Value> {
        FlagEvaluation(evaluate(key, as: type, default: defaultValue))
    }
}
