# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases take their notes from this file, so the section for a version has to exist before that
version can be tagged. See [Releasing](CONTRIBUTING.md#releasing).

## [Unreleased]

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
