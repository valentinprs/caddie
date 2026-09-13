// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CaddieCore", platforms: [.macOS(.v14)], products: [.library(name: "CaddieCore", targets: ["CaddieCore"])], targets: [.target(name: "CaddieCore", path: "Caddie/Core"), .testTarget(name: "CaddieCoreTests", dependencies: ["CaddieCore"], path: "Tests/CaddieCoreTests")])
