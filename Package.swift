// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PeekBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PeekBar",
            path: "Sources/PeekBar",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/PeekBar/Info.plist"])
            ]
        )
    ]
)
