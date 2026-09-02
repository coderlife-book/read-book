// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "ReadBookCore", targets: ["ReadBookCore"]),
]

var targets: [Target] = [
    .target(name: "ReadBookCore"),
    .testTarget(
        name: "ReadBookCoreTests",
        dependencies: ["ReadBookCore"],
        resources: [.copy("Fixtures")]
    ),
]

#if os(macOS)
products.append(.executable(name: "ReadBook", targets: ["ReadBook"]))
targets.insert(
    .executableTarget(
        name: "ReadBook",
        dependencies: [.target(name: "ReadBookCore")]
    ),
    at: 1
)
targets.append(
    .testTarget(
        name: "ReadBookAppTests",
        dependencies: [.target(name: "ReadBook")]
    )
)
#endif

let package = Package(
    name: "ReadBook",
    platforms: [.macOS("26.0")],
    products: products,
    targets: targets
)
