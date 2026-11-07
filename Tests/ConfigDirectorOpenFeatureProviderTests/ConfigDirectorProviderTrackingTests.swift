import ConfigDirector
@testable import ConfigDirectorOpenFeatureProvider
import Foundation
import OpenFeature
import Testing

struct ConfigDirectorProviderTrackingTests {
    private let client = FakeClient()

    @Test func forwardsTheEventNameValueAndAttributes() {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)

        provider.track(
            key: "checkout-completed",
            context: nil,
            details: ImmutableTrackingEventDetails(
                value: 49.9,
                structure: ImmutableStructure(attributes: ["plan": .string("pro")])
            )
        )

        #expect(client.trackCalls == [
            FakeClient.TrackCall(eventName: "checkout-completed", value: 49.9, details: ["plan": "pro"]),
        ])
    }

    @Test func forwardsAnEventWithoutDetailsWithoutAValueOrDetails() {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)

        provider.track(key: "app-opened", context: nil, details: nil)

        #expect(client.trackCalls == [FakeClient.TrackCall(eventName: "app-opened")])
    }

    @Test func forwardsAValueWithoutAttributesWithoutDetails() {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)

        provider.track(
            key: "checkout-completed",
            context: nil,
            details: ImmutableTrackingEventDetails(value: 49.9)
        )

        #expect(client.trackCalls == [FakeClient.TrackCall(eventName: "checkout-completed", value: 49.9)])
    }

    @Test func forwardsAttributesWithoutAValue() {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)

        provider.track(
            key: "checkout-completed",
            context: nil,
            details: ImmutableTrackingEventDetails(attributes: ["plan": .string("pro")])
        )

        #expect(client.trackCalls == [
            FakeClient.TrackCall(eventName: "checkout-completed", details: ["plan": "pro"]),
        ])
    }

    @Test func mapsEveryKindOfAttribute() {
        let provider = ConfigDirectorProvider(client: client, ownsClient: true)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

        provider.track(
            key: "checkout-completed",
            context: nil,
            details: ImmutableTrackingEventDetails(attributes: [
                "trial": .boolean(true),
                "plan": .string("pro"),
                "seats": .integer(12),
                "ratio": .double(0.5),
                "startedAt": .date(startedAt),
                "regions": .list([.string("us-east"), .integer(2)]),
                "billing": .structure(["cycle": .string("yearly")]),
                "coupon": .null,
            ])
        )

        #expect(client.trackCalls == [
            FakeClient.TrackCall(eventName: "checkout-completed", details: [
                "trial": true,
                "plan": "pro",
                "seats": 12,
                "ratio": 0.5,
                "startedAt": .date(startedAt),
                "regions": ["us-east", 2],
                "billing": ["cycle": "yearly"],
                "coupon": nil,
            ]),
        ])
    }
}
