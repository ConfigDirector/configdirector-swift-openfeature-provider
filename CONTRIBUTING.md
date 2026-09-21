# Contributing

## Building and testing

```bash
swift build
swift test
```

CI also runs `swiftformat --lint .` and `swiftlint lint --strict`, builds the package for iOS, tvOS
and watchOS, and builds the sample app. Run the first two before pushing:

```bash
swiftformat .
swiftlint lint --strict
```

The tests need no SDK key and no network. The integration tests start an HTTP server on localhost
and point the real ConfigDirector client at it, which is how they check what the provider sends to
ConfigDirector, including the name and version it reports.

## The sample app

[Samples/ConfigDirectorOpenFeatureSample.xcodeproj](Samples/ConfigDirectorOpenFeatureSample.xcodeproj)
depends on the released provider the way a consumer's app would, so opening the project on its own
builds the released provider, not your working tree.

[Samples/ConfigDirectorOpenFeatureSample-Local.xcworkspace](Samples/ConfigDirectorOpenFeatureSample-Local.xcworkspace)
holds the sample project alongside this repository's package root, and a local package in a
workspace takes precedence over a remote dependency with the same identity. Work on the provider
through the workspace; it is what CI builds:

```bash
xcodebuild -workspace Samples/ConfigDirectorOpenFeatureSample-Local.xcworkspace \
  -scheme ConfigDirectorOpenFeatureSample -destination 'generic/platform=iOS Simulator' build
```

Building it needs no SDK key. Without one the app says so and runs anyway.

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
