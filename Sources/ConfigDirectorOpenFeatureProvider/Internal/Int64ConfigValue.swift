import ConfigDirector

struct Int64ConfigValue: ConfigValue, CustomStringConvertible {
    static var configValueKind: ConfigValueKind {
        .number
    }

    let rawValue: Int64

    var description: String {
        String(rawValue)
    }

    init(_ rawValue: Int64) {
        self.rawValue = rawValue
    }

    init?(configValue: String) {
        if let whole = Int64(configValue) {
            rawValue = whole
            return
        }

        guard let parsed = Double(configValue: configValue),
              let truncated = Int64(exactly: parsed.rounded(.towardZero))
        else { return nil }

        rawValue = truncated
    }
}
