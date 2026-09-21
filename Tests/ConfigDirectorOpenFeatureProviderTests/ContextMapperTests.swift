import ConfigDirector
@testable import ConfigDirectorOpenFeatureProvider
import Foundation
import OpenFeature
import Testing

struct ContextMapperTests {
    @Test func mapsAMissingContextToAnEmptyConfigDirectorContext() {
        #expect(ConfigDirectorContext(evaluationContext: nil) == ConfigDirectorContext())
    }

    @Test func mapsAnEmptyContextToAnEmptyConfigDirectorContext() {
        #expect(ConfigDirectorContext(evaluationContext: ImmutableContext()) == ConfigDirectorContext())
    }

    @Test func mapsTheTargetingKeyToTheID() {
        let context = ImmutableContext(targetingKey: "user-123")

        #expect(ConfigDirectorContext(evaluationContext: context).id == "user-123")
    }

    @Test func fallsBackToTheIDAttributeWithoutATargetingKey() {
        let context = ImmutableContext(attributes: ["id": .string("user-456")])

        #expect(ConfigDirectorContext(evaluationContext: context).id == "user-456")
    }

    @Test func acceptsAnIntegerIDAttribute() {
        let context = ImmutableContext(attributes: ["id": .integer(42)])

        #expect(ConfigDirectorContext(evaluationContext: context).id == "42")
    }

    @Test func prefersTheTargetingKeyOverTheIDAttribute() {
        let context = ImmutableContext(attributes: ["id": .string("user-456")])
            .withTargetingKey("user-123")

        #expect(ConfigDirectorContext(evaluationContext: context).id == "user-123")
    }

    @Test func mapsTheNameTraitsAndAnonymousAttributes() {
        let context = ImmutableContext(attributes: [
            "name": .string("Ada"),
            "anonymous": .boolean(true),
            "traits": .structure([
                "plan": .string("pro"),
                "seats": .integer(12),
                "ratio": .double(0.5),
                "beta": .boolean(true),
                "nothing": .null,
                "regions": .list([.string("us-east"), .string("eu-west")]),
                "company": .structure(["size": .integer(250)]),
            ]),
        ]).withTargetingKey("user-123")

        #expect(ConfigDirectorContext(evaluationContext: context) == ConfigDirectorContext(
            id: "user-123",
            name: "Ada",
            traits: [
                "plan": "pro",
                "seats": 12,
                "ratio": 0.5,
                "beta": true,
                "nothing": nil,
                "regions": ["us-east", "eu-west"],
                "company": ["size": 250],
            ],
            isAnonymous: true
        ))
    }

    @Test func ignoresAttributesConfigDirectorHasNoFieldFor() {
        let context = ImmutableContext(attributes: ["plan": .string("pro")])

        #expect(ConfigDirectorContext(evaluationContext: context) == ConfigDirectorContext())
    }

    @Test func leavesOutTraitsThatAreEmptyOrNotAStructure() {
        let empty = ImmutableContext(attributes: ["traits": .structure([:])])
        let notAStructure = ImmutableContext(attributes: ["traits": .string("pro")])

        #expect(ConfigDirectorContext(evaluationContext: empty).traits == nil)
        #expect(ConfigDirectorContext(evaluationContext: notAStructure).traits == nil)
    }

    @Test func leavesOutAnAnonymousAttributeThatIsNotABoolean() {
        let context = ImmutableContext(attributes: ["anonymous": .string("true")])

        #expect(ConfigDirectorContext(evaluationContext: context).isAnonymous == nil)
    }

    @Test func leavesOutANameThatIsNotText() {
        let context = ImmutableContext(attributes: ["name": .boolean(true)])

        #expect(ConfigDirectorContext(evaluationContext: context).name == nil)
    }

    @Test func turnsDatesInsideTraitsIntoUTCISO8601Strings() {
        let signedUpAt = Date(timeIntervalSince1970: 1_700_000_000.5)
        let context = ImmutableContext(attributes: [
            "traits": .structure(["signedUpAt": .date(signedUpAt)]),
        ])

        #expect(ConfigDirectorContext(evaluationContext: context).traits == [
            "signedUpAt": "2023-11-14T22:13:20.500Z",
        ])
    }
}
