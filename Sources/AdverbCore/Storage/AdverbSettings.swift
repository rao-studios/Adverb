//
//  AdverbSettings.swift
//  AdverbCore
//
//  WHAT: The person's settings, in ~/.rao/apps/adverb/settings.json: the working directory, the
//        music folder, the model and how hard it thinks, the renderer, the switches, and the
//        voice-over defaults (narrate or not, the last voice and model, the languages to make).
//  PIN:  Never an API key: those are in the Keychain. Decoding is tolerant: a field added later
//        reads as its default from an older file.
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
    public var version: Int = 1
    public var workdir: String?
    public var musicFolder: String?
    public var model: String
    public var effort: String
    public var fallbacks: Bool
    public var webFetch: Bool
    public var reviewPass: Bool
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
    /// The last ElevenLabs voice chosen: the next campaign's default.
    public var voiceID: String?
    public var voiceName: String?
    public var voiceModel: String
    /// The languages to narrate in after a day's English is confirmed: the saved preference.
    public var voiceLanguages: [Language]

    public static let voiceModels: [(id: String, title: String)] = [
        ("eleven_multilingual_v2", "Multilingual v2 · 29 languages"),
        ("eleven_v3", "Eleven v3 · most expressive"),
        ("eleven_flash_v2_5", "Flash v2.5 · half the price"),
    ]

    public static let models: [(id: String, title: String)] = [
        ("claude-opus-5-5", "Claude Opus 5.5"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-fable-5-1", "Claude Fable 5.1"),
    ]
    public static let efforts = ["low", "medium", "high", "xhigh", "max"]

    public init(workdir: String? = nil, musicFolder: String? = nil, model: String = "claude-opus-5-5", effort: String = "high",
                fallbacks: Bool = true, webFetch: Bool = true, reviewPass: Bool = true, buildConcurrency: Int = 2,
                renderer: RendererKind = .native, supersample: Bool = false, bitrateMbps: Int = 12, skillPath: String? = nil,
                lastProjectSlug: String? = nil, voiceOverDefault: Bool = false, voiceID: String? = nil, voiceName: String? = nil,
                voiceModel: String = VoiceSelection.defaultModel, voiceLanguages: [Language] = []) {
        self.workdir = workdir; self.musicFolder = musicFolder; self.model = model; self.effort = effort
        self.fallbacks = fallbacks; self.webFetch = webFetch; self.reviewPass = reviewPass
        self.buildConcurrency = buildConcurrency; self.renderer = renderer; self.supersample = supersample
        self.bitrateMbps = bitrateMbps; self.skillPath = skillPath; self.lastProjectSlug = lastProjectSlug
        self.voiceOverDefault = voiceOverDefault; self.voiceID = voiceID; self.voiceName = voiceName
        self.voiceModel = voiceModel; self.voiceLanguages = voiceLanguages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AdverbSettings()
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        workdir = try? c.decode(String.self, forKey: .workdir)
        musicFolder = try? c.decode(String.self, forKey: .musicFolder)
        model = (try? c.decode(String.self, forKey: .model)) ?? d.model
        effort = (try? c.decode(String.self, forKey: .effort)) ?? d.effort
        fallbacks = (try? c.decode(Bool.self, forKey: .fallbacks)) ?? d.fallbacks
        webFetch = (try? c.decode(Bool.self, forKey: .webFetch)) ?? d.webFetch
        reviewPass = (try? c.decode(Bool.self, forKey: .reviewPass)) ?? d.reviewPass
        buildConcurrency = (try? c.decode(Int.self, forKey: .buildConcurrency)) ?? d.buildConcurrency
        renderer = (try? c.decode(RendererKind.self, forKey: .renderer)) ?? d.renderer
        supersample = (try? c.decode(Bool.self, forKey: .supersample)) ?? d.supersample
        bitrateMbps = (try? c.decode(Int.self, forKey: .bitrateMbps)) ?? d.bitrateMbps
        skillPath = try? c.decode(String.self, forKey: .skillPath)
        lastProjectSlug = try? c.decode(String.self, forKey: .lastProjectSlug)
        voiceOverDefault = (try? c.decode(Bool.self, forKey: .voiceOverDefault)) ?? d.voiceOverDefault
        voiceID = try? c.decode(String.self, forKey: .voiceID)
        voiceName = try? c.decode(String.self, forKey: .voiceName)
        voiceModel = (try? c.decode(String.self, forKey: .voiceModel)) ?? d.voiceModel
        // As codes, so one this build does not know drops only itself, not the list.
        voiceLanguages = Language.decode((try? c.decode([String].self, forKey: .voiceLanguages)) ?? [])
    }

    /// The remembered voice, as a campaign would take it.
    public var voiceSelection: VoiceSelection? {
        voiceID.map { VoiceSelection(voiceID: $0, voiceName: voiceName ?? $0, modelID: voiceModel) }
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
