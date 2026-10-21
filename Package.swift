// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iCalendarParser",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
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
