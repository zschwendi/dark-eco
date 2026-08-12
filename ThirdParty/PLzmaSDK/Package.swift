// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "PLzmaSDK",
    products: [
        .library(name: "PLzmaSDK", targets: ["PLzmaSDK"]),
        .library(name: "PLzmaSDK-Static", type: .static, targets: ["PLzmaSDK"]),
        .library(name: "PLzmaSDK-Dynamic", type: .dynamic, targets: ["PLzmaSDK"])
    ],
    targets: [
        .target(name: "libplzma",
                path: "src",
                cSettings: [
                    .define("LIBPLZMA_VERSION_BUILD", to: "1448"),
                    .define("LIBPLZMA_NO_CRYPTO", to: "1"),
                    .define("LIBPLZMA_NO_TAR", to: "1"),
                    .unsafeFlags(["-fPIC"])
                ],
                cxxSettings: [
                    .define("LIBPLZMA_VERSION_BUILD", to: "1448"),
                    .define("LIBPLZMA_NO_CRYPTO", to: "1"),
                    .define("LIBPLZMA_NO_TAR", to: "1"),
                    .unsafeFlags(["-fPIC", "-fno-rtti"])
                ]),
        .target(name: "PLzmaSDK",
                dependencies: [
                    .target(name: "libplzma")
                ],
                path: "swift",
                resources: [
                    .copy("../resources/PrivacyInfo.xcprivacy"),
                ])
    ],
    swiftLanguageModes: [.v5, .v6],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx11
)
