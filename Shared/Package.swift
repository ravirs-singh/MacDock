// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacDockProtocol",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MacDockProtocol", targets: ["MacDockProtocol"])
    ],
    targets: [
        .target(name: "MacDockProtocol")
    ]
)
