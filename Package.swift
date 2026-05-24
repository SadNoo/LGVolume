// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LGVolume",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LGVolume", targets: ["LGVolume"])
    ],
    targets: [
        .executableTarget(
            name: "LGVolume",
            path: "Sources/LGVolume"
        )
    ]
)
