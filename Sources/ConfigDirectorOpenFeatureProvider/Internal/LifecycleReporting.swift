import OpenFeature

enum LifecycleCall {
    case initialization
    case contextUpdate

    var startEvent: ProviderEvent? {
        switch self {
        case .initialization:
            nil
        case .contextUpdate:
            .reconciling()
        }
    }

    var failureMessage: String {
        switch self {
        case .initialization:
            """
            ConfigDirector did not become ready during initialization. Flags resolve to their in-code \
            default values until the connection succeeds.
            """
        case .contextUpdate:
            """
            ConfigDirector did not become ready after the context changed. Flags resolve against the \
            previous context until the connection succeeds.
            """
        }
    }
}

enum LifecycleOutcome {
    case overtakenByALaterCall
    case ready
    case contextChanged
    case readyThenContextChanged
    case error
}

struct LifecycleReporting {
    private var latestCallNumber = 0
    private var isInitializationReported = false

    mutating func numberNextCall() -> Int {
        latestCallNumber += 1
        return latestCallNumber
    }

    mutating func outcome(
        of call: LifecycleCall,
        numbered number: Int,
        isClientReady: Bool
    ) -> LifecycleOutcome {
        guard number == latestCallNumber else { return .overtakenByALaterCall }
        defer { isInitializationReported = true }
        guard isClientReady else { return .error }
        switch call {
        case .initialization:
            return .ready
        case .contextUpdate where isInitializationReported:
            return .contextChanged
        case .contextUpdate:
            return .readyThenContextChanged
        }
    }
}
