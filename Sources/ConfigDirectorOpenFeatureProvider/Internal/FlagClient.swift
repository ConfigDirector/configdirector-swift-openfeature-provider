import ConfigDirector

protocol FlagClient: Sendable {
    var isReady: Bool { get }
    var events: AsyncStream<ClientEvent> { get }

    func initialize(context: ConfigDirectorContext?) async
    func updateContext(_ context: ConfigDirectorContext) async
    func value<Value: ConfigValue>(for key: String, default defaultValue: Value) -> Value
    func value<Value: Decodable & Sendable>(
        for key: String,
        as type: Value.Type,
        default defaultValue: Value
    ) -> Value
    func close()
}

extension ConfigDirectorClient: FlagClient {}
