// swift-tools-version: 5.7
import PackageDescription

let package = Package(
  name: "CuePad",
  platforms: [
    .macOS(.v13), // Need macOS 13+ for modern Network APIs
  ],
  products: [
    .library(
      name: "ATVRemote",
      targets: ["ATVRemote"]
    ),
  ],
  dependencies: [
    // Crypto utilities
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    // Protobuf for MRP protocol
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
    // BigInt for SRP authentication
    .package(url: "https://github.com/attaswift/BigInt.git", from: "5.3.0"),
  ],
  targets: [
    .target(
      name: "ATVRemote",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        .product(name: "BigInt", package: "BigInt"),
      ],
      path: "CuePad/ATVRemote"
    ),
  ]
)
