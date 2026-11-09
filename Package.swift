// swift-tools-version: 6.1
//
//  Package.swift
//  Adverb
//
//  Created by Ritesh Pakala on 10/26/26.
//  Copyright © 2026 Rao Studios LLC.
//
// WHAT: One SwiftPM package. Targets under Sources/, layered by name.
// OUT:  AdverbCore → AdverbRender / AdverbModels / AdverbVoice / AdverbAgents → AdverbRuntime → AdverbApp (Adverb.app)
// PIN:  AdverbCore names nothing: Foundation, the models, the stores, the prompts, and the seams every
//       generative step is made through (LanguageModel, SpeechProvider). AdverbModels names Frigate (MLX)
//       and nothing of Granite: the on-device language and vision models. AdverbVoice names Core ML and
//       nothing of Granite: Kokoro, the on-device voice. AdverbRender names WebKit, AVFoundation and
//       Accelerate and nothing of Granite: the renderer, the encoder, the beat tracker, the captions, the
//       sheets. AdverbAgents names Granite and holds Craft's @Agent engine (Granite/, lifted whole) and
//       Adverb's agents, which see the models only through AdverbCore's seams. AdverbRuntime is the
//       composition: services, the root, the models and the voice put behind the seams.
//       NOTHING CALLS A REMOTE API. The only network use is downloading a pinned model from
//       huggingface.co/rao-studios (AdverbModels, AdverbVoice).
//       EVERY DEPENDENCY IS A URL, NEVER A PATH (Craft's rule).
//       Platforms are "26.0" (string), as Support/Info.plist says; make-app.sh checks they agree.
//       Swift 5 language mode everywhere, as Craft and Ambient build: the copied engine, Frigate's MLX
//       types and AVFoundation's non-Sendable writers compile unchanged.
//       MLX needs mlx.metallib beside the running binary: Scripts/build-metallib.sh puts it there
//       (dev.sh, test.sh and make-app.sh run it).

import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Adverb",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Adverb", targets: ["AdverbApp"]),
        .executable(name: "adverb-render-probe", targets: ["RenderProbe"]),
        .executable(name: "adverb-model-probe", targets: ["ModelProbe"]),
        .library(name: "AdverbCore", targets: ["AdverbCore"]),
        .library(name: "AdverbModels", targets: ["AdverbModels"]),
        .library(name: "AdverbVoice", targets: ["AdverbVoice"]),
        .library(name: "AdverbAgents", targets: ["AdverbAgents"]),
        .library(name: "AdverbRender", targets: ["AdverbRender"]),
        .library(name: "AdverbRuntime", targets: ["AdverbRuntime"]),
    ],
    dependencies: [
        // Granite's main carries the compile hook @Agent needs (GraniteCustomEvent).
        .package(url: "https://github.com/riteshpakala/Granite.git", branch: "main"),
        // The on-device stack: MLX, mlx-swift-lm (LLM and VLM), the Hub client and its downloader.
        .package(url: "https://github.com/rao-studios/Frigate.git", branch: "main"),
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
            linkerSettings: [.linkedFramework("WebKit"), .linkedFramework("JavaScriptCore"), .linkedFramework("AVFoundation"),
                             .linkedFramework("Accelerate")]
        ),
        // MARK: - AdverbModels — the on-device language and vision models (MLX, through Frigate).
        .target(
            name: "AdverbModels",
            dependencies: [
                "AdverbCore",
                .product(name: "MLX", package: "Frigate"),
                .product(name: "MLXLLM", package: "Frigate"),
                .product(name: "MLXVLM", package: "Frigate"),
                .product(name: "MLXLMCommon", package: "Frigate"),
                .product(name: "FrigateBridge", package: "Frigate"),
                .product(name: "FrigateHub", package: "Frigate"),
                .product(name: "FrigateParallel", package: "Frigate"),
            ],
            path: "Sources/AdverbModels",
            swiftSettings: v5
        ),
        // MARK: - AdverbVoice — Kokoro, the on-device voice (Core ML), lifted from Ambient.
        .target(
            name: "AdverbVoice",
            dependencies: ["AdverbCore", .product(name: "FrigateHub", package: "Frigate")],
            path: "Sources/AdverbVoice",
            swiftSettings: v5,
            linkerSettings: [.linkedFramework("CoreML"), .linkedFramework("AVFoundation"), .linkedFramework("Accelerate")]
        ),
        // MARK: - AdverbAgents — @Agent and the agents, over AdverbCore's seams.
        .target(
            name: "AdverbAgents",
            dependencies: ["AdverbCore", "AdverbRender", .product(name: "Granite", package: "Granite")],
            path: "Sources/AdverbAgents",
            swiftSettings: v5
        ),
        // MARK: - AdverbRuntime — services and the root.
        .target(
            name: "AdverbRuntime",
            dependencies: ["AdverbCore", "AdverbAgents", "AdverbRender", "AdverbModels", "AdverbVoice",
                           .product(name: "Granite", package: "Granite")],
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
        // MARK: - The model probe: the generative steps headless, on a campaign on disk, timed —
        // a plan, a day's sheet, a voice line. How models are compared against the reference sheets.
        .executableTarget(
            name: "ModelProbe",
            dependencies: ["AdverbAgents", "AdverbModels", "AdverbVoice", "AdverbRender", "AdverbCore"],
            path: "Sources/Probes/ModelProbe",
            swiftSettings: v5
        ),
        // MARK: - Tests (Swift Testing). Fixtures are read beside the sources, not as resources.
        .testTarget(name: "AdverbCoreTests", dependencies: ["AdverbCore"], path: "Tests/AdverbCoreTests", exclude: ["Fixtures"], swiftSettings: v5),
        .testTarget(name: "AdverbRenderTests", dependencies: ["AdverbRender", "AdverbCore"], path: "Tests/AdverbRenderTests", exclude: ["Fixtures"], swiftSettings: v5),
        .testTarget(name: "AdverbAgentsTests", dependencies: ["AdverbAgents", "AdverbCore", "AdverbRender", .product(name: "Granite", package: "Granite")],
                    path: "Tests/AdverbAgentsTests", swiftSettings: v5),
        .testTarget(name: "AdverbVoiceTests", dependencies: ["AdverbVoice", "AdverbCore"], path: "Tests/AdverbVoiceTests", swiftSettings: v5),
        .testTarget(name: "AdverbModelsTests", dependencies: ["AdverbModels", "AdverbCore",
                                                         .product(name: "MLX", package: "Frigate"),
                                                         .product(name: "MLXLMCommon", package: "Frigate"),
                                                         .product(name: "FrigateParallel", package: "Frigate")],
                    path: "Tests/AdverbModelsTests", swiftSettings: v5),
        .testTarget(name: "AdverbAppTests", dependencies: ["AdverbApp"], path: "Tests/AdverbAppTests", swiftSettings: v5),
    ]
)
