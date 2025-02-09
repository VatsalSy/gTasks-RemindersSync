// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "gTasks-RemindersSync",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/google/google-api-objectivec-client-for-rest.git", from: "3.0.0"),
        .package(url: "https://github.com/google/GTMAppAuth.git", from: "1.3.1"),
        .package(url: "https://github.com/openid/AppAuth-iOS.git", from: "1.6.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "gTasks-RemindersSync",
            dependencies: [
                .product(name: "GoogleAPIClientForRESTCore", package: "google-api-objectivec-client-for-rest"),
                .product(name: "GoogleAPIClientForREST_Tasks", package: "google-api-objectivec-client-for-rest"),
                "GTMAppAuth",
                .product(name: "AppAuth", package: "AppAuth-iOS")
            ]
        )
    ]
)
