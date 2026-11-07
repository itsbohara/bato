// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bato",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BatoCore", targets: ["BatoCore"]),
        .library(name: "BatoPersistence", targets: ["BatoPersistence"]),
        .library(name: "BatoRuntime", targets: ["BatoRuntime"]),
        .library(name: "BatoBlocking", targets: ["BatoBlocking"]),
        .library(name: "BatoBrowserUI", targets: ["BatoBrowserUI"]),
        .executable(name: "BatoShell", targets: ["BatoShell"]),
    ],
    targets: [
        .target(name: "BatoCore"),
        .target(name: "BatoPersistence", dependencies: ["BatoCore"]),
        .target(name: "BatoRuntime", dependencies: ["BatoCore"]),
        .target(name: "BatoImport", dependencies: ["BatoCore", "BatoPersistence"]),
        .target(name: "BatoBlocking"),
        .target(name: "BatoBrowserUI", dependencies: ["BatoCore", "BatoPersistence", "BatoRuntime", "BatoImport", "BatoBlocking"]),
        .executableTarget(name: "BatoShell", dependencies: ["BatoCore", "BatoPersistence"]),
        .testTarget(name: "BatoCoreTests", dependencies: ["BatoCore"]),
        .testTarget(name: "BatoPersistenceTests", dependencies: ["BatoPersistence", "BatoCore"]),
        .testTarget(name: "BatoRuntimeTests", dependencies: ["BatoRuntime", "BatoCore"]),
        .testTarget(name: "BatoBlockingTests", dependencies: ["BatoBlocking"]),
        .testTarget(name: "BatoImportTests", dependencies: ["BatoImport", "BatoCore", "BatoPersistence"]),
        .testTarget(name: "BatoShellTests", dependencies: ["BatoShell"]),
    ]
)
