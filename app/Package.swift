// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bato",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BatoCore", targets: ["BatoCore"]),
        .library(name: "BatoPersistence", targets: ["BatoPersistence"]),
        .library(name: "BatoRuntime", targets: ["BatoRuntime"]),
        .executable(name: "BatoShell", targets: ["BatoShell"]),
    ],
    targets: [
        .target(name: "BatoCore"),
        .target(name: "BatoPersistence", dependencies: ["BatoCore"]),
        .target(name: "BatoRuntime", dependencies: ["BatoCore"]),
        .executableTarget(name: "BatoShell", dependencies: ["BatoCore", "BatoPersistence"]),
        .testTarget(name: "BatoCoreTests", dependencies: ["BatoCore"]),
        .testTarget(name: "BatoPersistenceTests", dependencies: ["BatoPersistence"]),
        .testTarget(name: "BatoRuntimeTests", dependencies: ["BatoRuntime", "BatoCore"]),
        .testTarget(name: "BatoShellTests", dependencies: ["BatoShell"]),
    ]
)
