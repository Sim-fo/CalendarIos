// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarIosCore",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "CalendarIosCore",
            targets: ["CalendarIosCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "CalendarIosCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources",
            exclude: [
                "App"
            ]
        )
    ]
)
