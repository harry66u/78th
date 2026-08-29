// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScheduleEngine",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "ScheduleEngine", targets: ["ScheduleEngine"])
    ],
    targets: [
        .target(name: "ScheduleEngine"),
        .testTarget(name: "ScheduleEngineTests", dependencies: ["ScheduleEngine"])
    ]
)
