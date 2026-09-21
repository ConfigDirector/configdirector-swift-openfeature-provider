# ConfigDirector OpenFeature Provider for Swift

[![CI][ci-badge]][ci] [![Release][release-badge]][release]

[OpenFeature](https://openfeature.dev) provider for [ConfigDirector](https://www.configdirector.com), remote config and feature flags with typed values, JSON Schema validation, and safe renames of live flags. Start free, no card required.

It plugs the [ConfigDirector Swift SDK](https://github.com/ConfigDirector/swift-client-sdk) into the [OpenFeature Swift SDK](https://github.com/open-feature/swift-sdk), and supports iOS, iPadOS, macOS, tvOS, and watchOS.

## Install

In Xcode, go to **File → Add Package Dependencies…** and enter the package URL `https://github.com/ConfigDirector/swift-openfeature-provider`. In a Swift package, declare it in `Package.swift` alongside the OpenFeature Swift SDK:

```swift
dependencies: [
    .package(url: "https://github.com/ConfigDirector/swift-openfeature-provider", from: "0.1.0"),
    .package(url: "https://github.com/open-feature/swift-sdk", from: "0.6.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "ConfigDirectorOpenFeatureProvider", package: "swift-openfeature-provider"),
            .product(name: "OpenFeature", package: "swift-sdk"),
        ]
    ),
]
```

## Retrieve a value

```swift
import ConfigDirectorOpenFeatureProvider
import OpenFeature

let provider = try ConfigDirectorProvider(clientSDKKey: "YOUR-CLIENT-SDK-KEY")
await OpenFeatureAPI.shared.setProviderAndWait(
    provider: provider,
    initialContext: ImmutableContext(targetingKey: "user-123")
)

let client = OpenFeatureAPI.shared.getClient()
let darkMode = client.getBooleanValue(key: "dark-mode", defaultValue: false)
```

When ConfigDirector cannot be reached in time, the provider reports an error status. It keeps trying to connect and reports ready once it succeeds; until then flags resolve to their default values.

The types that configure the underlying ConfigDirector client are exported from the provider's module, so configuring it needs no second import:

```swift
let provider = try ConfigDirectorProvider(
    clientSDKKey: "YOUR-CLIENT-SDK-KEY",
    options: ConfigDirectorClientOptions(
        connection: ConnectionOptions(mode: .polling, pollingInterval: 120),
        logger: ConsoleLogger(level: .debug)
    )
)
```

## Evaluation context

The OpenFeature evaluation context is sent to ConfigDirector as the user's context:

| OpenFeature                     | ConfigDirector |
| ------------------------------- | -------------- |
| the targeting key, or else `id` | `id`           |
| `name`                          | `name`         |
| `traits`, a structure           | `traits`       |
| `anonymous`, a boolean          | `anonymous`    |

Any other attribute is ignored. Put the values your targeting rules depend on inside `traits`:

```swift
await OpenFeatureAPI.shared.setEvaluationContextAndWait(
    evaluationContext: ImmutableContext(
        targetingKey: "user-123",
        structure: ImmutableStructure(attributes: [
            "name": .string("Ada"),
            "traits": .structure(["plan": .string("pro")]),
        ])
    )
)
```

## Shutting down

The OpenFeature Swift SDK does not shut providers down. The provider closes its connection when it is released, which happens after `OpenFeatureAPI.shared.clearProvider()` as long as you hold no other reference to it. To close it while you still hold one, call `provider.close()`.

## Sample app

[Samples](Samples) holds an iOS and iPadOS app that reads flags through OpenFeature and re-renders as their values change.

## Documentation

Refer to the [official documentation for the Swift SDK](https://docs.configdirector.com/sdks/mobile/swift) for the options the provider accepts, and to the [OpenFeature Swift SDK reference](https://openfeature.dev/docs/reference/sdks/client/swift) for evaluating flags, handling events and writing hooks.

There is also [a quickstart guide for ConfigDirector and any of our SDKs](https://docs.configdirector.com/getting-started/quickstart).

## Getting Help

- [Ask a question in Discussions](https://github.com/orgs/ConfigDirector/discussions)
- [Contact support](https://www.configdirector.com/support)

[//]: # "links"
[ci-badge]: https://github.com/ConfigDirector/swift-openfeature-provider/actions/workflows/ci.yml/badge.svg
[ci]: https://github.com/ConfigDirector/swift-openfeature-provider/actions/workflows/ci.yml
[release-badge]: https://img.shields.io/github/v/release/ConfigDirector/swift-openfeature-provider
[release]: https://github.com/ConfigDirector/swift-openfeature-provider/releases
