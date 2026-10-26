// swift-tools-version: 6.1
//
//  Package.swift
//  Adverb
//
//  Created by Ritesh Pakala on 10/26/26.
//  Copyright © 2026 Rao Studios LLC.
//
// WHAT: One SwiftPM package. Targets under Sources/, layered by name.
// OUT:  AdverbCore → AdverbAgents / AdverbRender → AdverbRuntime → AdverbApp (Adverb.app)
// PIN:  AdverbCore names nothing: Foundation, the models, the stores, the Claude client, the
//       prompts. AdverbAgents names Granite and holds Craft's @Agent engine (Granite/, lifted
//       whole: Granite, Foundation and Combine only) and Adverb's agents. AdverbRender names
//       WebKit, AVFoundation and Accelerate and nothing of Granite: the renderer, the encoder, the
//       beat tracker, the captions. AdverbRuntime is the composition: services, the root.
//       EVERY DEPENDENCY IS A URL, NEVER A PATH (Craft's rule).
//       Platforms are "26.0" (string), as Support/Info.plist says; make-app.sh checks they agree.
//       Swift 5 language mode everywhere, as Craft and Ambient build: the copied engine and
//       AVFoundation's non-Sendable writers compile unchanged.

import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Adverb",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Adverb", targets: ["AdverbApp"]),
        .executable(name: "adverb-render-probe", targets: ["RenderProbe"]),
        .library(name: "AdverbCore", targets: ["AdverbCore"]),
        .library(name: "AdverbAgents", targets: ["AdverbAgents"]),
        .library(name: "AdverbRender", targets: ["AdverbRender"]),
        .library(name: "AdverbRuntime", targets: ["AdverbRuntime"]),
    ],
    dependencies: [
        // Granite's main carries the compile hook @Agent needs (GraniteCustomEvent).
        .package(url: "https://github.com/riteshpakala/Granite.git", branch: "main"),
    ],
    targets: [
        // MARK: - AdverbCore — Foundation only.
        .target(
            name: "AdverbCore",
            path: "Sources/AdverbCore",
            resources: [.copy("Resources")],
            swiftSettings: v5
        ),
        // MARK: - AdverbRender — the page to MP4, beats, sheets, captions.
        .target(
            name: "AdverbRender",
            dependencies: ["AdverbCore"],
            path: "Sources/AdverbRender",
            swiftSettings: v5,
            linkerSettings: [.linkedFramework("WebKit"), .linkedFramework("AVFoundation"), .linkedFramework("Accelerate")]
        ),
        // MARK: - AdverbAgents — @Agent and the Claude agents.
        .target(
            name: "AdverbAgents",
            dependencies: ["AdverbCore", "AdverbRender", .product(name: "Granite", package: "Granite")],
            path: "Sources/AdverbAgents",
            swiftSettings: v5
        ),
        // MARK: - AdverbRuntime — services and the root.
        .target(
            name: "AdverbRuntime",
            dependencies: ["AdverbCore", "AdverbAgents", "AdverbRender", .product(name: "Granite", package: "Granite")],
            path: "Sources/AdverbRuntime",
            swiftSettings: v5
        ),
        // MARK: - Adverb — the Mac app. AppKit owns the process, SwiftUI every surface.
        .executableTarget(
            name: "AdverbApp",
            dependencies: ["AdverbRuntime", "AdverbCore", "AdverbAgents", "AdverbRender", .product(name: "Granite", package: "Granite")],
            path: "Sources/AdverbApp",
            resources: [.copy("Resources")],
            swiftSettings: v5,
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(Context.packageDirectory)/Support/Info.plist",
                ]),
            ]
        ),
        // MARK: - The render probe: one page to frames and an MP4, timed. The feasibility check
        // the renderer was built against, kept as a diagnostic.
        .executableTarget(
            name: "RenderProbe",
            dependencies: ["AdverbRender", "AdverbCore"],
            path: "Sources/Probes/RenderProbe",
            swiftSettings: v5
        ),
        // MARK: - Tests (Swift Testing). Fixtures are read beside the sources, not as resources.
        .testTarget(name: "AdverbCoreTests", dependencies: ["AdverbCore"], path: "Tests/AdverbCoreTests", exclude: ["Fixtures"], swiftSettings: v5),
        .testTarget(name: "AdverbRenderTests", dependencies: ["AdverbRender", "AdverbCore"], path: "Tests/AdverbRenderTests", exclude: ["Fixtures"], swiftSettings: v5),
        .testTarget(name: "AdverbAgentsTests", dependencies: ["AdverbAgents", "AdverbCore", .product(name: "Granite", package: "Granite")], path: "Tests/AdverbAgentsTests", swiftSettings: v5),
        .testTarget(name: "AdverbAppTests", dependencies: ["AdverbApp"], path: "Tests/AdverbAppTests", swiftSettings: v5),
    ]
)
