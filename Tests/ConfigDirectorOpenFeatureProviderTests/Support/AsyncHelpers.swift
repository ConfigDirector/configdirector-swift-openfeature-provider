import Combine
@testable import ConfigDirectorOpenFeatureProvider
import Foundation
import OpenFeature

func waitUntil(timeout: TimeInterval = 2, _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return condition()
}

final class EventRecorder: Sendable {
    private let events = Locked<[ProviderEvent]>([])
    private let subscription = Locked<AnyCancellable?>(nil)

    init(_ publisher: AnyPublisher<ProviderEvent, Never>) {
        let cancellable = publisher.sink { [events] event in
            events.withLock { $0.append(event) }
        }
        subscription.withLock { $0 = cancellable }
    }

    var recorded: [ProviderEvent] {
        events.withLock { $0 }
    }

    func waitFor(count: Int) async -> [ProviderEvent] {
        _ = await waitUntil { self.recorded.count >= count }
        return recorded
    }

    func settled() async -> [ProviderEvent] {
        try? await Task.sleep(nanoseconds: 100_000_000)
        return recorded
    }
}
