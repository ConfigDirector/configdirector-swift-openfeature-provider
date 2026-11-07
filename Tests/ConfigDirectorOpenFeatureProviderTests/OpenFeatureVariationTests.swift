@testable import ConfigDirectorOpenFeatureProvider
import Foundation
import OpenFeature
import Testing

struct OpenFeatureVariationTests {
    private static let treatment = ServedVariation(id: "variation-treatment", name: "treatment")

    private static let servedConfigs = [
        ServedConfig(
            "checkout-cta-copy",
            "string",
            "Try it free",
            variation: treatment,
            ruleID: "rule-1",
            shareID: "share-treatment"
        ),
        ServedConfig(
            "unnamed-copy",
            "string",
            "Try it free",
            variation: ServedVariation(id: "variation-unnamed", name: nil)
        ),
        ServedConfig(
            "empty-name-copy",
            "string",
            "Try it free",
            variation: ServedVariation(id: "variation-empty-name", name: "")
        ),
        ServedConfig("dark-mode", "boolean", "true"),
        ServedConfig(
            "checkout-layout",
            "json",
            #"{"columns":2}"#,
            variation: treatment,
            ruleID: "rule-1",
            shareID: "share-treatment"
        ),
        ServedConfig(
            "checkout-regions",
            "json",
            #"["eu","us"]"#,
            variation: treatment,
            ruleID: "rule-1",
            shareID: "share-treatment"
        ),
        ServedConfig(
            "checkout-limit",
            "json",
            "42",
            variation: treatment,
            ruleID: "rule-1",
            shareID: "share-treatment"
        ),
    ]

    private let server: StubServer
    private let api = OpenFeatureAPI()
    private let provider: ConfigDirectorProvider

    init() async throws {
        server = try await StubServer(serving: Self.servedConfigs)
        provider = try ConfigDirectorProvider(
            clientSDKKey: "sdk-key",
            options: ConfigDirectorClientOptions(
                connection: ConnectionOptions(mode: .polling, timeout: 5, baseURL: server.baseURL),
                caching: CachingOptions(enabled: false),
                logger: ConsoleLogger(level: .off)
            )
        )
        await api.setProviderAndWait(provider: provider)
    }

    private func closeAndReadReportedEvaluation(of key: String) async throws -> ReceivedEvaluation {
        provider.close()
        let server = server
        _ = await waitUntil { !server.reportedEvaluations(of: key).isEmpty }
        return try #require(server.reportedEvaluations(of: key).first)
    }

    @Test func theVariantIsTheVariationNameOnAConfigWithVariations() {
        let details = api.getClient().getStringDetails(
            key: "checkout-cta-copy",
            defaultValue: "in-code default"
        )

        #expect(details.value == "Try it free")
        #expect(details.variant == "treatment")
        #expect(details.reason == "TARGETING_MATCH")
    }

    @Test func theVariantIsTheValueIDOnAConfigWithoutVariations() {
        let details = api.getClient().getBooleanDetails(key: "dark-mode", defaultValue: false)

        #expect(details.value == true)
        #expect(details.variant == "dark-mode-value")
        #expect(details.reason == "TARGETING_MATCH")
    }

    @Test func theVariantIsTheValueIDForAnUnnamedVariation() {
        let details = api.getClient().getStringDetails(key: "unnamed-copy", defaultValue: "in-code default")

        #expect(details.variant == "unnamed-copy-value")
    }

    @Test func theVariantIsTheValueIDForAVariationWithAnEmptyName() {
        let details = api.getClient().getStringDetails(
            key: "empty-name-copy",
            defaultValue: "in-code default"
        )

        #expect(details.variant == "empty-name-copy-value")
    }

    @Test func anObjectFlagResolvesWithTheVariationName() {
        let details = api.getClient().getObjectDetails(key: "checkout-layout", defaultValue: .structure([:]))

        #expect(details.value == .structure(["columns": .integer(2)]))
        #expect(details.variant == "treatment")
    }

    @Test func aListFlagResolvesWithTheVariationName() {
        let details = api.getClient().getObjectDetails(key: "checkout-regions", defaultValue: .list([]))

        #expect(details.value == .list([.string("eu"), .string("us")]))
        #expect(details.variant == "treatment")
    }

    @Test func anAfterHookReceivesTheVariationName() throws {
        let hook = RecordingHook<String>()
        api.addHooks(hooks: hook)

        _ = api.getClient().getStringValue(key: "checkout-cta-copy", defaultValue: "in-code default")

        let details = try #require(hook.afterDetails.first)
        #expect(details.variant == "treatment")
    }

    @Test func reportsTheRuleShareAndVariationOfAnEvaluation() async throws {
        _ = api.getClient().getStringValue(key: "checkout-cta-copy", defaultValue: "in-code default")

        let reported = try await closeAndReadReportedEvaluation(of: "checkout-cta-copy")

        #expect(reported.usedDefault == false)
        #expect(reported.evaluationReason == "found-match")
        #expect(reported.ruleId == "rule-1")
        #expect(reported.shareId == "share-treatment")
        #expect(reported.variationId == "variation-treatment")
    }

    @Test func reportsTheRuleShareAndVariationOfAnObjectFlagOfTheRightShape() async throws {
        _ = api.getClient().getObjectValue(key: "checkout-layout", defaultValue: .structure([:]))

        let reported = try await closeAndReadReportedEvaluation(of: "checkout-layout")

        #expect(reported.usedDefault == false)
        #expect(reported.evaluationReason == "found-match")
        #expect(reported.ruleId == "rule-1")
        #expect(reported.shareId == "share-treatment")
        #expect(reported.variationId == "variation-treatment")
    }

    @Test func reportsTheRuleShareAndVariationOfAListFlagOfTheRightShape() async throws {
        _ = api.getClient().getObjectValue(key: "checkout-regions", defaultValue: .list([]))

        let reported = try await closeAndReadReportedEvaluation(of: "checkout-regions")

        #expect(reported.usedDefault == false)
        #expect(reported.evaluationReason == "found-match")
        #expect(reported.ruleId == "rule-1")
        #expect(reported.shareId == "share-treatment")
        #expect(reported.variationId == "variation-treatment")
    }

    @Test func anInCodeDefaultValueThatIsNoStructureOrListReportsTheRuleShareAndVariation() async throws {
        _ = api.getClient().getObjectValue(key: "checkout-limit", defaultValue: .null)

        let reported = try await closeAndReadReportedEvaluation(of: "checkout-limit")

        #expect(reported.usedDefault == false)
        #expect(reported.evaluationReason == "found-match")
        #expect(reported.ruleId == "rule-1")
        #expect(reported.shareId == "share-treatment")
        #expect(reported.variationId == "variation-treatment")
    }

    @Test func anObjectFlagServedAnotherShapeReportsNoRuleShareOrVariation() async throws {
        let fallback = Value.structure(["columns": .integer(1)])

        let details = api.getClient().getObjectDetails(key: "checkout-limit", defaultValue: fallback)

        #expect(details.value == fallback)
        #expect(details.errorCode == .typeMismatch)
        #expect(details.variant == nil)
        let reported = try await closeAndReadReportedEvaluation(of: "checkout-limit")
        #expect(reported.usedDefault)
        #expect(reported.evaluationReason == "type-mismatch")
        #expect(reported.requestedType == "JSONObject")
        #expect(reported.defaultValue.valueId == "7WhQ2PHlVS5Qvd0Ixi3UjG")
        #expect(reported.ruleId == nil)
        #expect(reported.shareId == nil)
        #expect(reported.variationId == nil)
    }

    @Test func aListFlagServedAnObjectReportsNoRuleShareOrVariation() async throws {
        let fallback = Value.list([.string("eu")])

        let details = api.getClient().getObjectDetails(key: "checkout-layout", defaultValue: fallback)

        #expect(details.value == fallback)
        #expect(details.errorCode == .typeMismatch)
        #expect(details.variant == nil)
        let reported = try await closeAndReadReportedEvaluation(of: "checkout-layout")
        #expect(reported.usedDefault)
        #expect(reported.evaluationReason == "type-mismatch")
        #expect(reported.requestedType == "JSONArray")
        #expect(reported.defaultValue.valueId == "61sWJtTXhGn0BcRa3PwJxG")
        #expect(reported.ruleId == nil)
        #expect(reported.shareId == nil)
        #expect(reported.variationId == nil)
    }
}
