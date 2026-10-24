# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases take their notes from this file, so the section for a version has to exist before that
version can be tagged. See [Releasing](CONTRIBUTING.md#releasing).

## [Unreleased]

### Added

- The provider reports the `stale` status while the underlying client serves the values it kept on
  the device from an earlier launch, from the moment they are loaded until live values arrive and
  the provider reports `ready`. When the initial connection times out while those values are served,
  the provider reports `error` and then `stale` again, so `setProviderAndWait` behaves as before and
  flags resolve to the kept values instead of their default values. `CachingOptions` and
  `CachingProvider` are re-exported, so the `caching` option of `ConfigDirectorClientOptions` can be
  turned off or given a store of your own without importing `ConfigDirector`. Resolutions carry no
  reason, as before. Requires version 1.9.0 of the Swift client SDK, which keeps the values.

## [1.3.0] - 2026-10-15

### Added

- A top-level `kind` attribute of the evaluation context, beside the targeting key, is sent as the
  ConfigDirector context kind. It is read the way `id` is: a string as given, an integer as its
  text, and anything else as no context kind. Leaving it out means `user`, as before, and a `kind`
  inside `traits` stays an ordinary trait. Initializing or changing the context with an invalid
  context kind still succeeds and reports ready or a context change, never an error: the SDK logs
  an error, ignores the whole context, and flags resolve as if no context was set. Requires version
  1.8.0 of the Swift client SDK, which adds context kinds.

## [1.2.0] - 2026-10-01

### Added

- `init(injectedClient:)`, behind `@_spi(Testing)`, creates the provider over a `ConfigDirectorClient`
  the test owns: usually the `client` of a test client made with the Swift client SDK's
  `ConfigDirectorTesting` product, so code that reads flags through OpenFeature can be tested
  against values the test controls. The provider never closes a client it was given. Requires
  version 1.7.0 of the Swift client SDK.

### Changed

- Configuration-changed events list the keys of configs that a full update removed after the keys
  the update carried, so flags backed by a removed config re-evaluate to their default values.
  Requires version 1.6.0 of the Swift client SDK.

## [1.1.1] - 2026-09-26

- Bumped the dependency on `configdirector-swift-sdk` to pick up telemetry report fix.

## [1.1.0] - 2026-09-25

- Bumped the dependency on `configdirector-swift-sdk` to pick up evaluation type mismatch fixes.

## [1.0.0] - 2026-09-21

- Added the provider to the SDK functional test harness.

## [0.1.0] - 2026-09-21

### Added

- `ConfigDirectorProvider`, an OpenFeature provider for the OpenFeature Swift SDK backed by the
  ConfigDirector Swift client SDK. It reports its own name and version to ConfigDirector, which
  requires version 1.4.0 of the Swift client SDK.
