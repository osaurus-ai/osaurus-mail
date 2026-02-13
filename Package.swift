// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "osaurus-mail",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "osaurus-mail", type: .dynamic, targets: ["osaurus_mail"])
    ],
    targets: [
        .target(
            name: "osaurus_mail",
            path: "Sources/osaurus_mail"
        ),
        .testTarget(
            name: "osaurus_mailTests",
            dependencies: ["osaurus_mail"],
            path: "Tests/osaurus_mailTests"
        )
    ]
)