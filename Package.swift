// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iCalendarParser",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "iCalendarParser",
            targets: ["iCalendarParser"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "iCalendarParser",
            dependencies: []),
        .testTarget(
            name: "iCalendarParserTests",
            dependencies: ["iCalendarParser"])
    ]
)
