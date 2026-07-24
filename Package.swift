// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "osaurus-mail",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "osaurus-mail", type: .dynamic, targets: ["osaurus_mail"])
    ],
    dependencies: [
        .package(url: "https://github.com/osaurus-ai/osaurus-plugin-sdk.git", exact: "1.0.0")
    ],
    targets: [
        .target(
            name: "osaurus_mail",
            dependencies: [
                .product(name: "OsaurusPluginABI", package: "osaurus-plugin-sdk"),
                .product(name: "OsaurusPluginKit", package: "osaurus-plugin-sdk"),
            ],
            path: "Sources/osaurus_mail"
        ),
        .testTarget(
            name: "osaurus_mailTests",
            dependencies: [
                "osaurus_mail",
                .product(name: "OsaurusPluginTestSupport", package: "osaurus-plugin-sdk"),
            ],
            path: "Tests/osaurus_mailTests"
        )
    ]
)
