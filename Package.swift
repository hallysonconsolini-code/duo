// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Duo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Duo",
            dependencies: ["SwiftTerm"],
            path: "Sources/Duo"
        ),
    ]
)
