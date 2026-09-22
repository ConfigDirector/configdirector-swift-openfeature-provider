# Contributing

## Building and testing

```bash
swift build
swift test
```

The tests need no SDK key and no network. The integration tests start an HTTP server on localhost
and point the real ConfigDirector client at it, which is how they check what the provider sends to
ConfigDirector, including the name and version it reports.

## CI and the pre-push hook

[.github/workflows/ci.yml](.github/workflows/ci.yml) runs on every branch and pull request: build
and test, both linters, a compile for iOS, tvOS and watchOS, and a build of the four sample apps.

The same jobs run locally as a `pre-push` hook, in that order and with the same commands. Wire it
up once per clone:

```bash
git config core.hooksPath .githooks
```

It checks the working tree rather than the commits being pushed, so uncommitted changes are
included. Bypass it for a single push with `git push --no-verify`.

The cheap checks run first, so an unformatted file fails in seconds instead of after the platform
matrix. It needs SwiftLint and SwiftFormat on `PATH` and refuses to run without them, rather than
silently skipping a check CI will fail on:

```bash
brew install swiftlint swiftformat
```

The sample stage builds the local-override workspace described below, so it has the same
folder-name requirement: the hook fails at package resolution unless the clone is called
`configdirector-swift-openfeature-provider`.

## The sample apps

[Samples/ConfigDirectorOpenFeatureSample.xcodeproj](Samples/ConfigDirectorOpenFeatureSample.xcodeproj)
depends on the released provider the way a consumer's app would, so opening the project on its own
builds the four samples against the released provider, not your working tree.

[Samples/ConfigDirectorOpenFeatureSample-Local.xcworkspace](Samples/ConfigDirectorOpenFeatureSample-Local.xcworkspace)
holds the sample project alongside this repository's package root, and a local package in a
workspace takes precedence over a remote dependency with the same identity. Work on the provider
through the workspace; it is what CI builds:

```bash
xcodebuild -workspace Samples/ConfigDirectorOpenFeatureSample-Local.xcworkspace \
  -scheme ConfigDirectorOpenFeatureSample -destination 'generic/platform=iOS Simulator' build

xcodebuild -workspace Samples/ConfigDirectorOpenFeatureSample-Local.xcworkspace \
  -scheme ConfigDirectorOpenFeatureSampleMac -destination 'generic/platform=macOS' build

xcodebuild -workspace Samples/ConfigDirectorOpenFeatureSample-Local.xcworkspace \
  -scheme ConfigDirectorOpenFeatureSampleTV -destination 'generic/platform=tvOS Simulator' build

xcodebuild -workspace Samples/ConfigDirectorOpenFeatureSample-Local.xcworkspace \
  -scheme ConfigDirectorOpenFeatureSampleWatch -destination 'generic/platform=watchOS Simulator' build
```

Building them needs no SDK key. Without one each app says so and runs anyway. Building
`ConfigDirectorOpenFeatureSampleTV` needs the tvOS platform installed (`xcodebuild -downloadPlatform tvOS`), and
`ConfigDirectorOpenFeatureSampleWatch` the watchOS one.

The override depends on the name of the folder this repository is checked out into. Swift Package
Manager identifies a local package by its folder name and a remote one by the last component of its
URL, so the two only count as the same package when the folder is called
`configdirector-swift-openfeature-provider`, which is what `git clone` and CI's checkout produce.
In a folder with another name package resolution fails: with "no versions match the requirement"
before the first release, and with "unable to override package … because its identity … doesn't
match override's identity (directory name)" after it.

## Releasing

Swift Package Manager resolves a version straight from a git tag, so the tag *is* the release —
there is no artifact to upload and no registry to push to.

1. Rename the `## [Unreleased]` heading in [CHANGELOG.md](CHANGELOG.md) to
   `## [X.Y.Z] - YYYY-MM-DD`, and start a fresh empty `## [Unreleased]` above it.
2. Bump `providerVersion` in
   [Sources/ConfigDirectorOpenFeatureProvider/Internal/Constants.swift](Sources/ConfigDirectorOpenFeatureProvider/Internal/Constants.swift)
   to match.
3. Commit both, tag that commit `vX.Y.Z`, and push the tag.

A major bump needs one more edit: the sample's project pins the provider `upToNextMajorVersion`
from `0.1.0`, so it follows every `0.x` on its own and stops at `1.0.0`. Raise `minimumVersion` in
[Samples/ConfigDirectorOpenFeatureSample.xcodeproj/project.pbxproj](Samples/ConfigDirectorOpenFeatureSample.xcodeproj/project.pbxproj).
CI will not catch a stale pin — it builds the workspace, which never resolves the requirement at
all.

[.github/workflows/release.yml](.github/workflows/release.yml) does the rest: it checks the tag
against `Constants.providerVersion` and against CHANGELOG.md, runs the whole CI workflow — the same
jobs a branch push runs, via `workflow_call` rather than a second copy of the matrix — and only
then creates the GitHub release, using that changelog section as the notes. A tag with a hyphen in
it (`v1.0.0-rc.1`) is published as a prerelease.

Both checks run first because they are the cheapest jobs and the ones most likely to fail:

```bash
.github/scripts/check-release-version.sh v0.1.0
.github/scripts/changelog-section.sh 0.1.0
```

The version check exists because the provider reports `Constants.providerVersion` to ConfigDirector
as its own identity, in place of the Swift SDK's. A release tagged `v0.2.0` whose code reports
`0.1.0` cannot be attributed to what anyone actually installed, and nothing else in the build would
notice. The changelog check exists because the notes are read from that section — forgetting to
stamp the heading would otherwise ship a release with no notes at all.
