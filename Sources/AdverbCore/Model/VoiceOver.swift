//
//  VoiceOver.swift
//  AdverbCore
//
//  WHAT: An asset's narration: which ElevenLabs voice speaks it, the English track (Claude's
//        timed lines, each spoken as its own clip) and a track per other language, each with its
//        own videos, captions and transcript. Confirming the English is what unlocks the rest.
//  PIN:  Times in a line (`at`, `until`) are page time, the page's own seek(t); a clip's spoken
//        span is relative to the clip. So a re-cut that moves the scenes only re-places the clips
//        (through the asset's warp) and never asks ElevenLabs again. Clips and lines live on disk
//        (voice/<code>/), so a remix never re-spends characters.
//

import Foundation

/// The voice's dials, as ElevenLabs names them on the wire (its `settings` and `voice_settings`).
public struct VoiceSettings: Codable, Sendable, Equatable, Hashable {
    public var stability: Double
    public var similarityBoost: Double
    public var style: Double
    public var useSpeakerBoost: Bool
    /// 0.7…1.2; the fit rule raises it to at most 1.15 for a line that runs long.
    public var speed: Double

    public init(stability: Double = 0.5, similarityBoost: Double = 0.75, style: Double = 0, useSpeakerBoost: Bool = true, speed: Double = 1) {
        self.stability = stability; self.similarityBoost = similarityBoost; self.style = style
        self.useSpeakerBoost = useSpeakerBoost; self.speed = speed
    }

    enum CodingKeys: String, CodingKey {
        case stability, style, speed
        case similarityBoost = "similarity_boost"
        case useSpeakerBoost = "use_speaker_boost"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VoiceSettings()
        stability = (try? c.decode(Double.self, forKey: .stability)) ?? d.stability
        similarityBoost = (try? c.decode(Double.self, forKey: .similarityBoost)) ?? d.similarityBoost
        style = (try? c.decode(Double.self, forKey: .style)) ?? d.style
        useSpeakerBoost = (try? c.decode(Bool.self, forKey: .useSpeakerBoost)) ?? d.useSpeakerBoost
        speed = (try? c.decode(Double.self, forKey: .speed)) ?? d.speed
    }
}

/// The voice a campaign (or a day) is narrated with.
public struct VoiceSelection: Codable, Sendable, Equatable, Hashable {
    public var voiceID: String
    public var voiceName: String
    public var modelID: String
    public var settings: VoiceSettings

    public static let defaultModel = "eleven_multilingual_v2"

    public init(voiceID: String, voiceName: String, modelID: String = VoiceSelection.defaultModel, settings: VoiceSettings = .init()) {
        self.voiceID = voiceID; self.voiceName = voiceName; self.modelID = modelID; self.settings = settings
    }
}

/// One spoken word's span, relative to its clip.
public struct WordTiming: Codable, Sendable, Equatable, Hashable {
    public var text: String
    public var start: Double
    public var end: Double
    public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
}

/// One line of narration: what is said, the window it belongs in (page time), and once spoken,
/// its clip and when within the clip the speech starts and ends.
public struct NarrationLine: Codable, Sendable, Equatable, Hashable {
    public var index: Int
    public var text: String
    /// Page time the line starts at.
    public var at: Double
    /// Page time the line must be done by.
    public var until: Double
    public var spokenStart: Double?
    public var spokenEnd: Double?
    public var words: [WordTiming]
    /// Relative to the campaign folder.
    public var clipPath: String?
    public var clipSeconds: Double?
    public var characters: Int
    public var requestID: String?
    public var speed: Double
    /// Claude shortened it because the first take ran past its window.
    public var shortened: Bool
    /// Text, voice, model, language and speed: a clip with the same key is reused.
    public var cacheKey: String?

    public init(index: Int, text: String, at: Double, until: Double, spokenStart: Double? = nil, spokenEnd: Double? = nil,
                words: [WordTiming] = [], clipPath: String? = nil, clipSeconds: Double? = nil, characters: Int = 0,
                requestID: String? = nil, speed: Double = 1, shortened: Bool = false, cacheKey: String? = nil) {
        self.index = index; self.text = text; self.at = at; self.until = until; self.spokenStart = spokenStart
        self.spokenEnd = spokenEnd; self.words = words; self.clipPath = clipPath; self.clipSeconds = clipSeconds
        self.characters = characters; self.requestID = requestID; self.speed = speed; self.shortened = shortened; self.cacheKey = cacheKey
    }

    /// When the voice starts the line in the video: the line's page time through the warp, the
    /// moment its text arrives.
    public func speechStart(warp: TimeWarp?) -> Double { warp?.realTime(forPage: at) ?? at }

    /// When the clip starts in the video: early by its lead-in, so the first word is on the text.
    public func placedStart(warp: TimeWarp?) -> Double { max(0, speechStart(warp: warp) - (spokenStart ?? 0)) }

    /// The window the speech may fill, in seconds.
    public var window: Double { max(0, until - at) }

    public var isRecorded: Bool { clipPath != nil && spokenEnd != nil }
}

/// What voice/<code>/script.json holds: the record the clips are cached against.
public struct NarrationScript: Codable, Sendable, Equatable, Hashable {
    public var language: Language
    public var voiceID: String
    public var modelID: String
    public var lines: [NarrationLine]
    public var generatedAt: Date
    /// For a translation: the English text it was made from, so a changed English marks it stale.
    public var translatedFrom: [String]?

    public init(language: Language, voiceID: String, modelID: String, lines: [NarrationLine], generatedAt: Date = Date(), translatedFrom: [String]? = nil) {
        self.language = language; self.voiceID = voiceID; self.modelID = modelID; self.lines = lines
        self.generatedAt = generatedAt; self.translatedFrom = translatedFrom
    }
}

/// One language's narration and the files made with it.
public struct VoiceTrack: Codable, Sendable, Equatable, Hashable {
    public var language: Language
    /// voice/<code>/script.json, relative to the campaign folder.
    public var scriptPath: String
    public var lines: [NarrationLine]
    /// Empty for English: the asset's own renders are the English ones.
    public var renders: [Render]
    /// Keyed by orientation.rawValue, as A11y.captions is.
    public var captions: [String: CaptionFiles]
    public var transcriptPath: String?
    public var characters: Int
    public var generatedAt: Date
    /// The English it was translated from has changed since: translate again before using it.
    public var stale: Bool
    /// The English lines' text this track was translated from.
    public var translatedFrom: [String]?

    public init(language: Language, scriptPath: String, lines: [NarrationLine], renders: [Render] = [], captions: [String: CaptionFiles] = [:],
                transcriptPath: String? = nil, characters: Int = 0, generatedAt: Date = Date(), stale: Bool = false, translatedFrom: [String]? = nil) {
        self.language = language; self.scriptPath = scriptPath; self.lines = lines; self.renders = renders; self.captions = captions
        self.transcriptPath = transcriptPath; self.characters = characters; self.generatedAt = generatedAt; self.stale = stale
        self.translatedFrom = translatedFrom
    }

    public func render(_ orientation: Orientation) -> Render? { renders.first { $0.orientation == orientation } }

    /// Made and current: its videos exist and its English has not changed.
    public var isFresh: Bool { !stale && !renders.isEmpty }
}

public struct VoiceOver: Codable, Sendable, Equatable, Hashable {
    public var voiceID: String
    public var voiceName: String
    public var modelID: String
    public var settings: VoiceSettings
    public var english: VoiceTrack
    public var languages: [VoiceTrack]
    /// Set when the person has listened to the English and said it is right; cleared when the
    /// English changes. Languages are made only after it.
    public var confirmedAt: Date?
    public var appliedAt: Date

    public init(selection: VoiceSelection, english: VoiceTrack, languages: [VoiceTrack] = [], confirmedAt: Date? = nil, appliedAt: Date = Date()) {
        voiceID = selection.voiceID; voiceName = selection.voiceName; modelID = selection.modelID; settings = selection.settings
        self.english = english; self.languages = languages; self.confirmedAt = confirmedAt; self.appliedAt = appliedAt
    }

    public var selection: VoiceSelection { VoiceSelection(voiceID: voiceID, voiceName: voiceName, modelID: modelID, settings: settings) }
    public var isConfirmed: Bool { confirmedAt != nil }

    public func track(_ language: Language) -> VoiceTrack? {
        language == .english ? english : languages.first { $0.language == language }
    }

    /// The language tracks whose videos are made and current, in canonical order.
    public var freshLanguages: [Language] { languages.filter(\.isFresh).map(\.language).sorted() }

    public mutating func upsert(_ track: VoiceTrack) {
        if track.language == .english { english = track; return }
        if let i = languages.firstIndex(where: { $0.language == track.language }) { languages[i] = track } else { languages.append(track) }
        languages.sort { $0.language < $1.language }
    }
}

/// What a run spent at ElevenLabs.
public struct VoiceUsage: Codable, Sendable, Equatable, Hashable {
    public var characters: Int
    public var requests: Int
    public var modelID: String

    public init(characters: Int = 0, requests: Int = 0, modelID: String = VoiceSelection.defaultModel) {
        self.characters = characters; self.requests = requests; self.modelID = modelID
    }

    public static func + (a: VoiceUsage, b: VoiceUsage) -> VoiceUsage {
        VoiceUsage(characters: a.characters + b.characters, requests: a.requests + b.requests, modelID: b.characters > 0 ? b.modelID : a.modelID)
    }

    public var isEmpty: Bool { characters == 0 && requests == 0 }

    /// An estimate in US dollars at the API's list price per thousand characters.
    public func estimatedUSD() -> Double { Double(characters) / 1000 * Self.pricePer1k(modelID) }

    /// API list price per 1,000 characters (2026-10; verify at elevenlabs.io/pricing/api).
    public static func pricePer1k(_ model: String) -> Double {
        switch model {
        case "eleven_flash_v2_5", "eleven_flash_v2", "eleven_turbo_v2_5", "eleven_turbo_v2": 0.05
        case "eleven_v4_turbo": 0.04
        case "eleven_v4": 0.08
        default: 0.10
        }
    }

    public var line: String {
        String(format: "%@ characters in %d requests · ≈ $%.2f", characters.formatted(), requests, estimatedUSD())
    }
}

/// Where the ElevenLabs subscription stands: what Settings shows beside the key.
public struct VoiceQuota: Codable, Sendable, Equatable, Hashable {
    public var used: Int
    public var limit: Int
    public var resetsAt: Date?
    public var tier: String?

    public init(used: Int, limit: Int, resetsAt: Date? = nil, tier: String? = nil) {
        self.used = used; self.limit = limit; self.resetsAt = resetsAt; self.tier = tier
    }

    public var remaining: Int { max(0, limit - used) }
}

extension Campaign {
    /// Days built without a voice-over: what switching narration on can catch up.
    public var silentBuiltDays: [Int] {
        days.filter { $0.asset.map { !$0.renders.isEmpty && $0.voiceOver == nil } ?? false }.map(\.index)
    }

    public var isNarrated: Bool { brief.voiceOver != nil }
}
