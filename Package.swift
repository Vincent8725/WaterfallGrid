// swift-tools-version:5.9

//
//  Copyright © 2019 Paolo Leonardi.
//
//  Licensed under the MIT license. See the LICENSE file for more info.
//

import PackageDescription

let package = Package(
    name: "WaterfallGrid",
    platforms: [
        .iOS(.v14),
        .macOS(.v10_15),
        .tvOS(.v13),
        .visionOS(.v1),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "WaterfallGrid",
            targets: ["WaterfallGrid"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WaterfallGrid",
            dependencies: []),
        .testTarget(
            name: "WaterfallGridTests",
            dependencies: ["WaterfallGrid"]),
    ]
)
