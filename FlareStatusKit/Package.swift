// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlareStatusKit",
    platforms: [.tvOS(.v17), .iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "FlareStatusKit", targets: ["FlareStatusKit"])
    ],
    targets: [
        .target(name: "FlareStatusKit"),
        .testTarget(
            name: "FlareStatusKitTests",
            dependencies: ["FlareStatusKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
