// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MealieKit",
    defaultLocalization: "de",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MealieKit", targets: ["MealieKit"])
    ],
    targets: [
        .target(name: "MealieKit", resources: [.process("Resources")]),
        .testTarget(name: "MealieKitTests", dependencies: ["MealieKit"])
    ]
)
