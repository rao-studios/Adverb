//
//  AdverbSettings.swift
//  AdverbCore
//
//  WHAT: The person's settings, in ~/.rao/apps/adverb/settings.json: the working directory, the
//        music folder, the models (the writer, the eyes, the voice), whether the writer thinks
//        first, the sheet gate, the renderer, the switches, and the voice-over defaults (narrate or
//        not, the last voice, the languages to make).
//  PIN:  Decoding is tolerant: a field added later reads as its default from an older file, and a
//        field an older build wrote (the Claude model and effort, the ElevenLabs model) is dropped.
//

import Foundation

public enum RendererKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// WebKit snapshots into AVFoundation's encoder. No external tools.
    case native
    /// The skill's render path: Chrome through Playwright, frames into the same encoder.
    case chrome

    public var title: String { self == .native ? "Native (WebKit)" : "Chrome (Playwright)" }
}

public struct AdverbSettings: Codable, Sendable, Equatable {
    public var version: Int = 2
    public var workdir: String?
    public var musicFolder: String?
    /// The writer: plans, pages, voice-overs, translations (a ModelCatalog id, or any MLX repo or folder).
    public var textModel: String?
    /// The eyes, when the writer cannot read images. Nil: the writer's own, or none.
    public var visionModel: String?
    /// The folder models are kept in and looked for (a path, "~" allowed). Nil: ~/.rao/models.
    public var modelsFolder: String?
    /// Let the writer think before it plans and writes a page: slower, usually better.
    public var thinking: Bool
    /// Tokens the writer may think for before it must answer.
    public var thinkingBudget: Int
    /// The writer looks at its own stills and corrects the page (on the eyes it has).
    public var reviewPass: Bool
    /// A day stops at its contact sheet until it is approved; off, a sheet that passes its checks renders on.
    public var sheetGate: Bool
    /// Days written at once. Model calls take turns on the GPU; a second day overlaps stills and renders.
    public var buildConcurrency: Int
    public var renderer: RendererKind
    /// Paint each frame at 2× and downscale: finer edges, about twice the render time.
    public var supersample: Bool
    public var bitrateMbps: Int
    /// A SKILL.md to use instead of the bundled copy (the T9's, while editing the skill).
    public var skillPath: String?
    public var lastProjectSlug: String?
    /// New campaigns start with voice-over on.
    public var voiceOverDefault: Bool
    /// The last voice chosen: the next campaign's default.
    public var voiceID: String?
    public var voiceName: String?
    public var voicePack: String?
    /// The languages to narrate in after a day's English is confirmed: the saved preference.
    public var voiceLanguages: [Language]

    public init(workdir: String? = nil, musicFolder: String? = nil, textModel: String? = nil, visionModel: String? = nil,
                thinking: Bool = true, thinkingBudget: Int = 4_096, reviewPass: Bool = true, sheetGate: Bool = true,
                buildConcurrency: Int = 2, renderer: RendererKind = .native, supersample: Bool = false, bitrateMbps: Int = 12,
                skillPath: String? = nil, lastProjectSlug: String? = nil, voiceOverDefault: Bool = false, voiceID: String? = nil,
                voiceName: String? = nil, voicePack: String? = nil, voiceLanguages: [Language] = [], modelsFolder: String? = nil) {
        self.workdir = workdir; self.musicFolder = musicFolder; self.textModel = textModel; self.visionModel = visionModel
        self.thinking = thinking; self.thinkingBudget = thinkingBudget; self.reviewPass = reviewPass; self.sheetGate = sheetGate
        self.buildConcurrency = buildConcurrency; self.renderer = renderer; self.supersample = supersample
        self.bitrateMbps = bitrateMbps; self.skillPath = skillPath; self.lastProjectSlug = lastProjectSlug
        self.voiceOverDefault = voiceOverDefault; self.voiceID = voiceID; self.voiceName = voiceName; self.voicePack = voicePack
        self.voiceLanguages = voiceLanguages; self.modelsFolder = modelsFolder
    }

    enum CodingKeys: String, CodingKey {
        case version, workdir, musicFolder, textModel, visionModel, thinking, thinkingBudget, reviewPass, sheetGate, buildConcurrency,
             renderer, supersample, bitrateMbps, skillPath, lastProjectSlug, voiceOverDefault, voiceID, voiceName, voicePack, voiceLanguages,
             modelsFolder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AdverbSettings()
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        workdir = try? c.decode(String.self, forKey: .workdir)
        musicFolder = try? c.decode(String.self, forKey: .musicFolder)
        textModel = try? c.decode(String.self, forKey: .textModel)
        visionModel = try? c.decode(String.self, forKey: .visionModel)
        modelsFolder = (try? c.decode(String.self, forKey: .modelsFolder)).flatMap { $0.isEmpty ? nil : $0 }
        thinking = (try? c.decode(Bool.self, forKey: .thinking)) ?? d.thinking
        thinkingBudget = (try? c.decode(Int.self, forKey: .thinkingBudget)) ?? d.thinkingBudget
        reviewPass = (try? c.decode(Bool.self, forKey: .reviewPass)) ?? d.reviewPass
        sheetGate = (try? c.decode(Bool.self, forKey: .sheetGate)) ?? d.sheetGate
        buildConcurrency = (try? c.decode(Int.self, forKey: .buildConcurrency)) ?? d.buildConcurrency
        renderer = (try? c.decode(RendererKind.self, forKey: .renderer)) ?? d.renderer
        supersample = (try? c.decode(Bool.self, forKey: .supersample)) ?? d.supersample
        bitrateMbps = (try? c.decode(Int.self, forKey: .bitrateMbps)) ?? d.bitrateMbps
        skillPath = try? c.decode(String.self, forKey: .skillPath)
        lastProjectSlug = try? c.decode(String.self, forKey: .lastProjectSlug)
        voiceOverDefault = (try? c.decode(Bool.self, forKey: .voiceOverDefault)) ?? d.voiceOverDefault
        // An ElevenLabs voice id names no voice here: only a voice saved with its pack is kept.
        voicePack = try? c.decode(String.self, forKey: .voicePack)
        voiceID = voicePack == nil ? nil : try? c.decode(String.self, forKey: .voiceID)
        voiceName = voicePack == nil ? nil : try? c.decode(String.self, forKey: .voiceName)
        // As codes, so one this build does not know drops only itself, not the list.
        voiceLanguages = Language.decode((try? c.decode([String].self, forKey: .voiceLanguages)) ?? [])
    }

    /// The remembered voice, as a campaign would take it.
    public var voiceSelection: VoiceSelection? {
        guard let voiceID, let voicePack else { return nil }
        return VoiceSelection(voiceID: voiceID, voiceName: voiceName ?? voiceID, packID: voicePack)
    }

    /// The models folder as a URL (nil: ~/.rao/models).
    public var modelsFolderURL: URL? { modelsFolder.map(ModelHome.url) }

    /// The writer in use: the one chosen, while the catalog still offers it, else this Mac's default.
    public var textModelID: String {
        textModel.flatMap { ModelCatalog.spec($0)?.slot == .text ? $0 : nil } ?? ModelCatalog.recommended().text.id
    }

    public var workdirURL: URL? { workdir.map { URL(fileURLWithPath: $0, isDirectory: true) } }
    public var workspace: Workspace? { workdirURL.map(Workspace.init(workdir:)) }

    public static func load(from url: URL = AdverbHome.settingsFile) -> AdverbSettings {
        (try? JSONCoding.read(AdverbSettings.self, from: url)) ?? AdverbSettings()
    }

    public func save(to url: URL = AdverbHome.settingsFile) throws {
        try JSONCoding.write(self, to: url)
    }
}
