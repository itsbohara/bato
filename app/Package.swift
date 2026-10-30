// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bato",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BatoCore", targets: ["BatoCore"]),
        .library(name: "BatoPersistence", targets: ["BatoPersistence"]),
        .executable(name: "BatoShell", targets: ["BatoShell"]),
    ],
    targets: [
        .target(name: "BatoCore"),
        .target(name: "BatoPersistence", dependencies: ["BatoCore"]),
        .executableTarget(name: "BatoShell", dependencies: ["BatoCore", "BatoPersistence"]),
        .testTarget(name: "BatoCoreTests", dependencies: ["BatoCore"]),
        .testTarget(name: "BatoPersistenceTests", dependencies: ["BatoPersistence"]),
        .testTarget(name: "BatoShellTests", dependencies: ["BatoShell"]),
    ]
)
