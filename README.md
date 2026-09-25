# ConfigDirector OpenFeature Provider for Swift

[![CI][ci-badge]][ci] [![Release][release-badge]][release]

[OpenFeature](https://openfeature.dev) provider for [ConfigDirector](https://www.configdirector.com), remote config and feature flags with typed values, JSON Schema validation, and safe renames of live flags. Start free, no card required.

It plugs the [ConfigDirector Swift SDK](https://github.com/ConfigDirector/configdirector-swift-sdk) into the [OpenFeature Swift SDK](https://github.com/open-feature/swift-sdk), and supports iOS, iPadOS, macOS, tvOS, and watchOS.

## Install

In Xcode, go to **File → Add Package Dependencies…** and enter the package URL `https://github.com/ConfigDirector/configdirector-swift-openfeature-provider`. In a Swift package, declare it in `Package.swift` alongside the OpenFeature Swift SDK:

```swift
dependencies: [
    .package(url: "https://github.com/ConfigDirector/configdirector-swift-openfeature-provider", from: "1.1.0"),
    .package(url: "https://github.com/open-feature/swift-sdk", from: "0.6.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "ConfigDirectorOpenFeatureProvider", package: "configdirector-swift-openfeature-provider"),
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

Full details are in the [official documentation](https://docs.configdirector.com/sdks/openfeature/swift).

## Documentation

Refer to the [official documentation for the OpenFeature Swift provider](https://docs.configdirector.com/sdks/openfeature/swift).

There is also [a quickstart guide for ConfigDirector and any of our SDKs](https://docs.configdirector.com/getting-started/quickstart).

## Sample apps

[Samples](Samples) holds iOS and iPadOS, macOS, tvOS and watchOS apps that read flags through OpenFeature and re-render as their values change.

## Getting Help

- [Ask a question in Discussions](https://github.com/orgs/ConfigDirector/discussions)
- [Contact support](https://www.configdirector.com/support)

[//]: # "links"
[ci-badge]: https://github.com/ConfigDirector/configdirector-swift-openfeature-provider/actions/workflows/ci.yml/badge.svg
[ci]: https://github.com/ConfigDirector/configdirector-swift-openfeature-provider/actions/workflows/ci.yml
[release-badge]: https://img.shields.io/github/v/release/ConfigDirector/configdirector-swift-openfeature-provider
[release]: https://github.com/ConfigDirector/configdirector-swift-openfeature-provider/releases
