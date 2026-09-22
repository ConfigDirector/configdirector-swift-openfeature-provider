# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases take their notes from this file, so the section for a version has to exist before that
version can be tagged. See [Releasing](CONTRIBUTING.md#releasing).

## [Unreleased]

## [1.0.0] - 2026-09-21

- Added the provider to the SDK functional test harness.

## [0.1.0] - 2026-09-21

### Added

- `ConfigDirectorProvider`, an OpenFeature provider for the OpenFeature Swift SDK backed by the
  ConfigDirector Swift client SDK. It reports its own name and version to ConfigDirector, which
  requires version 1.4.0 of the Swift client SDK.
