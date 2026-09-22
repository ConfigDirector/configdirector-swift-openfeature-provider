# ConfigDirector OpenFeature sample apps

Four SwiftUI apps showing how to use the ConfigDirector OpenFeature provider for Swift: each reads a
handful of flags through the OpenFeature Swift SDK and re-renders as their values change.

[**ConfigDirectorOpenFeatureSample**](ConfigDirectorOpenFeatureSample) covers iOS and iPadOS as one universal target rather than an iPhone app and an iPad
app. The screen follows the horizontal size class: compact stacks the flags and the context in a
single list, regular moves the context into its own column beside them. That covers iPad, an iPad
Split View slice wide enough to be regular, and a landscape iPhone Pro Max.

[**ConfigDirectorOpenFeatureSampleMac**](ConfigDirectorOpenFeatureSampleMac) covers macOS, in an `HSplitView` so the divider between the context and the
flags is draggable the way a Mac window should be. It is sandboxed, and the sandbox is why the
target turns on outgoing network connections — without that entitlement the provider cannot reach
the server at all.

[**ConfigDirectorOpenFeatureSampleTV**](ConfigDirectorOpenFeatureSampleTV) covers tvOS, in a fixed two-column layout rather than a list. tvOS moves focus
with the remote and plain text rows do not take focus, so a scrolling list would be unreachable;
the five flags fit a 1080p screen without scrolling, and the picker is the one thing that needs to
be focusable.

[**ConfigDirectorOpenFeatureSampleWatch**](ConfigDirectorOpenFeatureSampleWatch) covers watchOS, standalone with no companion iPhone app. One scrolling
list, the provider status in the navigation title where there is room for it, and the context
picker on the separate screen watchOS gives a `Picker` by default.

Everything that touches OpenFeature lives in [Shared](Shared) and compiles into all four:
[the build-time settings](Shared/SampleConfiguration.swift), which create the provider and the
evaluation contexts, and [the views](Shared/FlagViews.swift), where provider events drive a SwiftUI
view. Each app adds only its entry point and its own layout, so they differ in presentation and not
in how they use OpenFeature. Nothing in them imports the ConfigDirector Swift SDK: the provider's
module exports the types that configure it.

## How they depend on the provider

The project adds the provider and the OpenFeature Swift SDK the way your own app would — as
released Swift packages, resolved from a version rather than from a path:

```
https://github.com/ConfigDirector/configdirector-swift-openfeature-provider.git
https://github.com/open-feature/swift-sdk.git
```

In Xcode that is **File → Add Package Dependencies…**, pasting each URL and taking the default
*Up to Next Major Version*. In a `Package.swift` it is:

```swift
dependencies: [
    .package(url: "https://github.com/ConfigDirector/configdirector-swift-openfeature-provider.git", from: "0.1.0"),
    .package(url: "https://github.com/open-feature/swift-sdk.git", from: "0.6.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "ConfigDirectorOpenFeatureProvider", package: "configdirector-swift-openfeature-provider"),
            .product(name: "OpenFeature", package: "swift-sdk"),
        ]
    ),
]
```

The modules you import are `ConfigDirectorOpenFeatureProvider` and `OpenFeature`. Nothing in these
apps depends on living inside the provider's repository.

## Running them

1. Copy the example config and fill in the client SDK key from your ConfigDirector dashboard:

   ```sh
   cp Config.local.example.xcconfig Config.local.xcconfig
   ```

2. Open the project, pick the `ConfigDirectorOpenFeatureSample`, `ConfigDirectorOpenFeatureSampleMac`,
   `ConfigDirectorOpenFeatureSampleTV` or `ConfigDirectorOpenFeatureSampleWatch` scheme, and run it on your Mac, a
   simulator or a device:

   ```sh
   open ConfigDirectorOpenFeatureSample.xcodeproj
   ```

   Xcode fetches the packages on first open, so that one needs a network connection.

`Config.local.xcconfig` is git-ignored, and all four apps read the same copy of it. Its values reach
them through the `Info.plist` and are read back with `Bundle.main.object(forInfoDictionaryKey:)`,
so nothing has to be committed. Without it each app builds and runs, and says it has no SDK key.

Alongside the key it carries the evaluation context the flags are evaluated against:
`CONFIGDIRECTOR_USER_ID` becomes the targeting key, `CONFIGDIRECTOR_USER_NAME` the `name`
attribute, and `CONFIGDIRECTOR_USER_ROLE` the `role` trait. Leave them empty and the flags are
evaluated without a context.

The Context picker switches between that configured user, a built-in beta tester carrying a `role`
trait, and an anonymous context. Each switch calls `OpenFeatureAPI.shared.setEvaluationContext`,
which has the provider reconnect and re-evaluate every flag against the new identity — the way to
watch a targeting rule take effect without rebuilding. The provider status follows along:
reconciling while the provider reconnects, ready once it has.

## Building them against a local checkout

Contributors to the provider need the opposite of the above: the same four apps compiled against
the working tree, so a breaking API change fails here instead of reaching someone's app.

[ConfigDirectorOpenFeatureSample-Local.xcworkspace](ConfigDirectorOpenFeatureSample-Local.xcworkspace)
is that. It holds the sample project alongside the provider's package root, and a local package in
a workspace wins over a remote dependency with the same identity — so every target builds against
`../Sources` and the provider is not fetched. The targets, schemes and settings are the same ones;
only where `ConfigDirectorOpenFeatureProvider` comes from changes.

```sh
open ConfigDirectorOpenFeatureSample-Local.xcworkspace
```

This is what CI builds. The override only takes effect when the repository is checked out into a
folder named `configdirector-swift-openfeature-provider` — see
[Contributing](../CONTRIBUTING.md#the-sample-apps).

## What they show

All four apps read the keys of the ConfigDirector sample project — `temporary-feature-flag`,
`permanent-kill-switch`, `integer-config`, `day-of-the-week-config` and `json-value-config`.
Pointing them at a project without them is fine: each flag falls back to the default value passed
alongside its key, which is what the screen shows until the provider is ready.

`json-value-config` is read with `getObjectValue`, which serves the JSON document as an OpenFeature
`Value`. The other four go through `getBooleanValue`, `getIntegerValue` and `getStringValue`.

Flags are not read from a view's `body`. Each row re-reads its flag when the provider emits an
event, which it does when it becomes ready, when the context changes, and when config state
arrives. The provider connects in streaming mode, so a value changed in the ConfigDirector dashboard
appears on screen without restarting them.
