//
//  ModelCatalog.swift
//  AdverbCore
//
//  WHAT: The models Adverb offers, each pinned to a commit of a repository under
//        huggingface.co/rao-studios: the writer (plans, pages, voice-overs, translations), the
//        eyes (reads the stills), the voices. And the set this Mac is offered first, by its memory.
//  PIN:  Literals, reviewed in a diff, never fetched (AIIModels' rule). A revision is a 40-hex
//        commit; nil only while a mirror is still to be published, and then the model cannot be
//        downloaded. Every repository here is a Rao mirror: the upstream it was made from is named
//        beside it, never fetched.
//  PIN:  A writer that reads images is the eyes as well (Gemma 4 and Ministral 3 do): no second model
//        is loaded. Offered for now: Gemma 4, Nemotron 3 Super, Ministral 3 (the user's choice,
//        2026-11-08). The Qwen mirrors stay published on rao-studios and are not listed here.
//

import Foundation

public enum ModelSlot: String, Codable, Sendable, CaseIterable, Hashable {
    /// Plans the month, writes each page, the voice-over and its translations.
    case text
    /// Reads the stills (the review pass), when the writer cannot.
    case vision
    /// Speaks the voice-over.
    case speech

    public var title: String {
        switch self {
        case .text: "Writer"
        case .vision: "Eyes"
        case .speech: "Voice"
        }
    }
}

public struct ModelSpec: Sendable, Equatable, Hashable, Identifiable {
    /// The repository: "rao-studios/gemma-4-31b-it-mlx-4bit".
    public var id: String
    public var revision: String?
    public var slot: ModelSlot
    public var title: String
    /// One line on what it is for, as onboarding and Settings say it.
    public var summary: String
    /// config.json's model_type, or "kokoro" for a voice pack.
    public var family: String
    public var downloadBytes: Int64
    public var minimumMemoryGB: Int
    public var contextTokens: Int
    public var acceptsImages: Bool
    public var license: String
    /// What the mirror was made from: "mlx-community/gemma-4-31b-it-4bit@696d436c…".
    public var upstream: String
    /// A voice pack's id (the speech slot): what a campaign's voice names.
    public var packID: String?
    /// The repository and commit this mirror copies byte for byte ("org/name@<40 hex>"): a copy of
    /// that, already on this Mac, is this model (ModelSearch). Nil for Rao's own conversions.
    public var sameWeightsAs: String?

    public init(id: String, revision: String?, slot: ModelSlot, title: String, summary: String, family: String,
                downloadBytes: Int64, minimumMemoryGB: Int, contextTokens: Int = 32_768, acceptsImages: Bool = false,
                license: String = "Apache-2.0", upstream: String, packID: String? = nil, sameWeightsAs: String? = nil) {
        self.id = id; self.revision = revision; self.slot = slot; self.title = title; self.summary = summary
        self.family = family; self.downloadBytes = downloadBytes; self.minimumMemoryGB = minimumMemoryGB
        self.contextTokens = contextTokens; self.acceptsImages = acceptsImages; self.license = license
        self.upstream = upstream; self.packID = packID; self.sameWeightsAs = sameWeightsAs
    }

    /// `sameWeightsAs`, split.
    public var sameWeights: (repo: String, commit: String)? {
        guard let value = sameWeightsAs, let at = value.lastIndex(of: "@") else { return nil }
        return (String(value[..<at]), String(value[value.index(after: at)...]))
    }

    public var isInstallable: Bool { revision != nil }
    public var url: URL { URL(string: "https://huggingface.co/\(id)")! }
    public var sizeGB: Double { Double(downloadBytes) / 1_073_741_824 }
    /// "17.2 GB", "53 MB".
    public var sizeLabel: String {
        sizeGB >= 1 ? String(format: "%.1f GB", sizeGB) : String(format: "%.0f MB", Double(downloadBytes) / 1_048_576)
    }

    public func fits(memoryGB: Int) -> Bool { memoryGB >= minimumMemoryGB }
}

/// What one Mac runs: a writer, eyes when the writer has none, and the voice packs.
public struct ModelSet: Sendable, Equatable {
    public var text: ModelSpec
    public var vision: ModelSpec?
    public var speech: [ModelSpec]

    public init(text: ModelSpec, vision: ModelSpec? = nil, speech: [ModelSpec]) {
        self.text = text; self.vision = vision; self.speech = speech
    }

    public var all: [ModelSpec] { [text] + (vision.map { [$0] } ?? []) + speech }
    public var downloadBytes: Int64 { all.reduce(0) { $0 + $1.downloadBytes } }
}

public enum ModelCatalog {
    // MARK: - Writers

    public static let gemma4 = ModelSpec(
        id: "rao-studios/gemma-4-31b-it-mlx-4bit", revision: "f8655066591a70b6c39e00517e0751bb38bc4b00", slot: .text, title: "Gemma 4 31B",
        summary: "The default writer: plans, pages and voice-overs in the most natural prose of the set, and it reads the stills itself. Google's, Apache-2.0.",
        family: "gemma4", downloadBytes: 18_444_436_193, minimumMemoryGB: 32, contextTokens: 262_144, acceptsImages: true,
        upstream: "mlx-community/gemma-4-31b-it-4bit@696d436c404745a59f30e4939a658162b0a9e57f",
        sameWeightsAs: "mlx-community/gemma-4-31b-it-4bit@696d436c404745a59f30e4939a658162b0a9e57f")

    public static let nemotronSuper = ModelSpec(
        id: "rao-studios/NVIDIA-Nemotron-3-Super-120B-A12B-mlx-4bit", revision: "e3a66d8cfc95fa391eacc718aa5971df160cd4f1",
        slot: .text, title: "Nemotron 3 Super 120B-A12B",
        summary: "The largest writer, for Macs with 96 GB or more. Text only: the eyes are a second model.",
        family: "nemotron_h", downloadBytes: 68_000_941_086, minimumMemoryGB: 96, contextTokens: 262_144,
        license: "NVIDIA Open Model License", upstream: "Craft's mirror (KnownModels.nemotronSuper)")

    // MARK: - Eyes

    public static let ministral3 = ModelSpec(
        id: "rao-studios/Ministral-3-8B-Instruct-2512-mlx-8bit", revision: "3d71052d4c126d816a5a73df75222ecee8de3036",
        slot: .text, title: "Ministral 3 8B",
        summary: "For Macs with 24–31 GB: writes and reads the stills; expect more redos to reach the bar. Also the eyes for a writer that cannot see. Shared with Sewn and Craft.",
        family: "mistral3", downloadBytes: 10_414_950_269, minimumMemoryGB: 24, contextTokens: 262_144, acceptsImages: true,
        license: "Apache-2.0", upstream: "AII's mirror (AIIModels vision)")

    // MARK: - Voices

    public static let paradeePackID = "paradee-af-heart"
    public static let kokoroPackID = "kokoro-82m-en"

    public static let paradee = ModelSpec(
        id: "rao-studios/kokoro-paradee-8m-coreml", revision: "0b1168b9a8fe4078abfeb8b857d6699a6a4ce942", slot: .speech,
        title: "Heart (Kokoro, distilled)",
        summary: "Kokoro's af_heart voice distilled to 8M parameters, with exact word timing at any line length. English.",
        family: "kokoro", downloadBytes: 55_926_761, minimumMemoryGB: 8,
        upstream: "MithrilMan/teacher-in-the-loop@115a6c0469632a84fbcc6c8ed0ad7b1e06154b92, converted by Ambient (2026-10-31)",
        packID: paradeePackID)

    public static let kokoro82M = ModelSpec(
        id: "rao-studios/kokoro-82m-coreml-en", revision: "2d5d158fc82d3f86c80ce6151e521f5dbb59c1ad", slot: .speech,
        title: "Kokoro 82M voices",
        summary: "Kokoro-82M with eight English voices, American and British. Built to take more languages.",
        family: "kokoro", downloadBytes: 697_746_320, minimumMemoryGB: 8,
        upstream: "hexgrad/Kokoro-82M v1.0, Core ML windows (FluidInference), as Mary ships them",
        packID: kokoroPackID)

    /// Writers, the default first.
    public static let text: [ModelSpec] = [gemma4, nemotronSuper, ministral3]
    /// Eyes: models that read images, for a writer that cannot (Nemotron).
    public static let vision: [ModelSpec] = [ministral3]
    public static let speech: [ModelSpec] = [paradee, kokoro82M]
    /// Every model once (Ministral 3 writes and is eyes).
    public static var all: [ModelSpec] {
        var seen = Set<String>()
        return (text + vision + speech).filter { seen.insert($0.id).inserted }
    }

    public static func spec(_ id: String) -> ModelSpec? { all.first { $0.id == id } }
    public static func speechSpec(pack: String) -> ModelSpec? { speech.first { $0.packID == pack } }
    public static func models(_ slot: ModelSlot) -> [ModelSpec] {
        switch slot {
        case .text: text
        case .vision: vision
        case .speech: speech
        }
    }

    /// What a Mac with `memoryGB` is offered first: Gemma 4 from 32 GB, Ministral 3 below. Both read
    /// images, so neither needs eyes. A Mac under 24 GB is below what either is rated for.
    public static func recommended(memoryGB: Int = physicalMemoryGB) -> ModelSet {
        ModelSet(text: memoryGB >= gemma4.minimumMemoryGB ? gemma4 : ministral3, vision: nil, speech: [paradee, kokoro82M])
    }

    /// The eyes for a writer: none when it reads images itself.
    public static func vision(for text: ModelSpec, memoryGB: Int = physicalMemoryGB) -> ModelSpec? {
        guard !text.acceptsImages else { return nil }
        let published = vision.filter(\.isInstallable)
        return published.first { $0.fits(memoryGB: memoryGB - text.minimumMemoryGB / 2) } ?? published.last
    }

    public static var physicalMemoryGB: Int { Int(ProcessInfo.processInfo.physicalMemory >> 30) }
}
