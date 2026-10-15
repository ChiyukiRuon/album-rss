// swift-tools-version: 6.2
// Album RSS 的 Swift 共享模块：一个清单，三个库。iOS App 只链接这里的产物。
import PackageDescription

let package = Package(
  name: "AlbumRSSKit",
  defaultLocalization: "zh-Hans",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "AlbumCore", targets: ["AlbumCore"]),
    .library(name: "AlbumProviders", targets: ["AlbumProviders"]),
    .library(name: "AlbumImages", targets: ["AlbumImages"]),
  ],
  dependencies: [
    // 版本固定，升级时同时更新 Package.resolved
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    .package(url: "https://github.com/kean/Nuke.git", exact: "13.2.0"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.14.2"),
  ],
  targets: [
    .target(
      name: "AlbumCore",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "SwiftSoup", package: "SwiftSoup"),
      ],
      path: "AlbumCore/Sources/AlbumCore"
    ),
    .testTarget(
      name: "AlbumCoreTests",
      dependencies: ["AlbumCore"],
      path: "AlbumCore/Tests/AlbumCoreTests"
    ),
    .target(
      name: "AlbumProviders",
      dependencies: ["AlbumCore"],
      path: "AlbumProviders/Sources/AlbumProviders"
    ),
    .testTarget(
      name: "AlbumProvidersTests",
      dependencies: ["AlbumProviders"],
      path: "AlbumProviders/Tests/AlbumProvidersTests"
    ),
    .target(
      name: "AlbumImages",
      dependencies: [
        "AlbumCore",
        .product(name: "Nuke", package: "Nuke"),
        .product(name: "NukeUI", package: "Nuke"),
      ],
      path: "AlbumImages/Sources/AlbumImages"
    ),
    .testTarget(
      name: "AlbumImagesTests",
      dependencies: ["AlbumImages"],
      path: "AlbumImages/Tests/AlbumImagesTests"
    ),
  ],
  swiftLanguageModes: [.v6]
)
