// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "ReadBookCore", targets: ["ReadBookCore"]),
]

let mlxAudio: Package.Dependency = .package(
    url: "https://github.com/Blaizzy/mlx-audio-swift.git",
    revision: "3506fb93cc3b9e4a642079d5384eaca0373962e6"
)

let mlxProducts: [Target.Dependency] = [
    .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
    .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
    .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
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
    .executableTarget(name: "ReadBook", dependencies: [.target(name: "ReadBookCore")] + mlxProducts),
    at: 1
)
targets.append(
    .testTarget(name: "ReadBookAppTests", dependencies: [.target(name: "ReadBook")] + mlxProducts)
)
#endif

let package = Package(
    name: "ReadBook",
    platforms: [.macOS("26.0")],
    products: products,
    dependencies: [mlxAudio],
    targets: targets
)
