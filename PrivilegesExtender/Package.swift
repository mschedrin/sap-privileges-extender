// swift-tools-version: 5.9

import PackageDescription

var targets: [Target] = [
    .target(
        name: "PrivilegesExtenderCore",
        dependencies: ["Yams"]
    ),
    .testTarget(
        name: "PrivilegesExtenderCoreTests",
        dependencies: ["PrivilegesExtenderCore"]
    ),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "PrivilegesExtender",
        dependencies: ["PrivilegesExtenderCore"]
    )
)
#endif

let package = Package(
    name: "PrivilegesExtender",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: targets
)
