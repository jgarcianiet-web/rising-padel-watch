// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PadelCore",
    // El core no toca UIKit, WatchKit, HealthKit ni CoreMotion: es lógica pura y sus
    // tests corren con `swift test`, sin simulador.
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "PadelCore", targets: ["PadelCore"]),
    ],
    targets: [
        .target(name: "PadelCore"),
        .testTarget(name: "PadelCoreTests", dependencies: ["PadelCore"]),
    ]
)
