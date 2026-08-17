// swift-tools-version: 5.9
//
// JanjanCore — 더잔잔의 순수 로직 모듈.
//
// SwiftUI·SwiftData·UIKit 을 일절 import 하지 않는다. Foundation 만 쓰기 때문에
// macOS 러너에서 `swift test --package-path Packages/JanjanCore` 로 시뮬레이터 없이
// 곧바로 검증할 수 있다. 재고 계산처럼 틀리면 안 되는 것은 전부 여기에 둔다.

import PackageDescription

let package = Package(
    name: "JanjanCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "JanjanCore", targets: ["JanjanCore"])
    ],
    targets: [
        .target(
            name: "JanjanCore",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "JanjanCoreTests",
            dependencies: ["JanjanCore"]
        )
    ]
)
