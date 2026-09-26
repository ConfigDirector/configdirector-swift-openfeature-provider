// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "configdirector-swift-openfeature-provider",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "ConfigDirectorOpenFeatureProvider", targets: ["ConfigDirectorOpenFeatureProvider"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ConfigDirector/configdirector-swift-sdk.git", from: "1.5.1"),
        .package(url: "https://github.com/open-feature/swift-sdk.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "ConfigDirectorOpenFeatureProvider",
            dependencies: [
                .product(name: "ConfigDirector", package: "configdirector-swift-sdk"),
                .product(name: "OpenFeature", package: "swift-sdk"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ConfigDirectorOpenFeatureProviderTests",
            dependencies: ["ConfigDirectorOpenFeatureProvider"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
