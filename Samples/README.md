# ConfigDirector OpenFeature sample app

A SwiftUI app showing how to use the ConfigDirector OpenFeature provider for Swift: it reads a
handful of flags through the OpenFeature Swift SDK and re-renders as their values change.

[**ConfigDirectorOpenFeatureSample**](ConfigDirectorOpenFeatureSample) covers iOS and iPadOS as one
universal target rather than an iPhone app and an iPad app. The screen follows the horizontal size
class: compact stacks the flags and the context in a single list, regular moves the context into
its own column beside them. That covers iPad, an iPad Split View slice wide enough to be regular,
and a landscape iPhone Pro Max.

Everything that touches OpenFeature lives in [Shared](Shared):
[the build-time settings](Shared/SampleConfiguration.swift), which create the provider and the
evaluation contexts, and [the views](Shared/FlagViews.swift), where provider events drive a SwiftUI
view. The app adds only its entry point and its layout. Nothing in it imports the ConfigDirector
Swift SDK: the provider's module exports the types that configure it.

## How it depends on the provider

The project adds the provider and the OpenFeature Swift SDK the way your own app would — as
released Swift packages, resolved from a version rather than from a path:

```
https://github.com/ConfigDirector/swift-openfeature-provider.git
https://github.com/open-feature/swift-sdk.git
```

In Xcode that is **File → Add Package Dependencies…**, pasting each URL and taking the default
*Up to Next Major Version*. In a `Package.swift` it is:

```swift
dependencies: [
    .package(url: "https://github.com/ConfigDirector/swift-openfeature-provider.git", from: "0.1.0"),
    .package(url: "https://github.com/open-feature/swift-sdk.git", from: "0.6.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "ConfigDirectorOpenFeatureProvider", package: "swift-openfeature-provider"),
            .product(name: "OpenFeature", package: "swift-sdk"),
        ]
    ),
]
```

The modules you import are `ConfigDirectorOpenFeatureProvider` and `OpenFeature`. Nothing in the
app depends on living inside the provider's repository.

## Running it

1. Copy the example config and fill in the client SDK key from your ConfigDirector dashboard:

   ```sh
   cp Config.local.example.xcconfig Config.local.xcconfig
   ```

2. Open the project, pick the `ConfigDirectorOpenFeatureSample` scheme, and run it on a simulator
   or a device:

   ```sh
   open ConfigDirectorOpenFeatureSample.xcodeproj
   ```

   Xcode fetches the packages on first open, so that one needs a network connection.

`Config.local.xcconfig` is git-ignored. Its values reach the app through the `Info.plist` and are
read back with `Bundle.main.object(forInfoDictionaryKey:)`, so nothing has to be committed. Without
it the app builds and runs, and says it has no SDK key.

Alongside the key it carries the evaluation context the flags are evaluated against:
`CONFIGDIRECTOR_USER_ID` becomes the targeting key, `CONFIGDIRECTOR_USER_NAME` the `name`
attribute, and `CONFIGDIRECTOR_USER_ROLE` the `role` trait. Leave them empty and the flags are
evaluated without a context.

The Context picker switches between that configured user, a built-in beta tester carrying a `role`
trait, and an anonymous context. Each switch calls `OpenFeatureAPI.shared.setEvaluationContext`,
which has the provider reconnect and re-evaluate every flag against the new identity — the way to
watch a targeting rule take effect without rebuilding. The status beside the Flags header follows
along: reconciling while the provider reconnects, ready once it has.

## Building it against a local checkout

Contributors to the provider need the opposite of the above: the same app compiled against the
working tree, so a breaking API change fails here instead of reaching someone's app.

[ConfigDirectorOpenFeatureSample-Local.xcworkspace](ConfigDirectorOpenFeatureSample-Local.xcworkspace)
is that. It holds the sample project alongside the provider's package root, and a local package in
a workspace wins over a remote dependency with the same identity — so the target builds against
`../Sources` and the provider is not fetched. The target, scheme and settings are the same ones;
only where `ConfigDirectorOpenFeatureProvider` comes from changes.

```sh
open ConfigDirectorOpenFeatureSample-Local.xcworkspace
```

This is what CI builds.

## What it shows

The app reads the keys of the ConfigDirector sample project — `temporary-feature-flag`,
`permanent-kill-switch`, `integer-config`, `day-of-the-week-config` and `json-value-config`.
Pointing it at a project without them is fine: each flag falls back to the default value passed
alongside its key, which is what the screen shows until the provider is ready.

`json-value-config` is read with `getObjectValue`, which serves the JSON document as an OpenFeature
`Value`. The other four go through `getBooleanValue`, `getIntegerValue` and `getStringValue`.

Flags are not read from a view's `body`. Each row re-reads its flag when the provider emits an
event, which it does when it becomes ready, when the context changes, and when config state
arrives. The provider connects in streaming mode, so a value changed in the ConfigDirector dashboard
appears on screen without restarting the app.
