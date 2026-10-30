// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CountMoney",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CountMoney", targets: ["CountMoneyApp"])
    ],
    targets: [
        .executableTarget(
            name: "CountMoneyApp",
            path: "Sources/CountMoneyApp",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CountMoneyAppTests",
            dependencies: ["CountMoneyApp"],
            path: "Tests/CountMoneyAppTests"
        )
    ]
)
