// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MonkShared",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", .upToNextMajor(from: "9.0.0")),
        .package(url: "https://github.com/RevenueCat/purchases-ios", .upToNextMajor(from: "5.50.1")),
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.36.1")),
        .package(url: "https://github.com/UserJot/userjot-ios", .upToNextMajor(from: "0.2.0"))
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MonkShared",
            targets: ["MonkShared"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MonkShared",
            dependencies: [
                .product(name: "GoogleSignIn", condition: .when(platforms: [.iOS])),
                .product(name: "RevenueCat"),
                .product(name: "RevenueCatUI", condition: .when(platforms: [.iOS])),
                .product(name: "PostHog", condition: .when(platforms: [.iOS])),
                .product(name: "UserJot", condition: .when(platforms: [.iOS]))
            ]
        ),
        .testTarget(
            name: "MonkSharedTests",
            dependencies: ["MonkShared"]
        ),
    ]
)
