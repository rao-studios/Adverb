//
//  VoiceOver.swift
//  AdverbCore
//
//  WHAT: An asset's narration: which voice speaks it (a voice of a pack on this Mac), the English
//        track (the writer's timed lines, each spoken as its own clip) and a track per other
//        language, each with its own videos, captions and transcript. Confirming the English is
//        what unlocks the rest.
//  PIN:  Times in a line (`at`, `until`) are page time, the page's own seek(t); a clip's spoken
//        span is relative to the clip. So a re-cut that moves the scenes only re-places the clips
//        (through the asset's warp) and never speaks them again. Clips and lines live on disk
//        (voice/<code>/), so a remix never speaks a line twice.
//

import Foundation

/// The voice a campaign (or a day) is narrated with: a voice of a pack on this Mac.
public struct VoiceSelection: Codable, Sendable, Equatable, Hashable {
    public var voiceID: String
    public var voiceName: String
    /// The voice pack (ModelCatalog's packID).
    public var packID: String
    /// 1 is the voice's own pace; a line that runs long is spoken again at up to 1.15×.
    public var speed: Double

    public static let defaultPack = ModelCatalog.paradeePackID
    public static let defaultVoice = "af_heart"

    public init(voiceID: String = VoiceSelection.defaultVoice, voiceName: String = "Heart", packID: String = VoiceSelection.defaultPack, speed: Double = 1) {
        self.voiceID = voiceID; self.voiceName = voiceName; self.packID = packID; self.speed = speed
    }

    public static let `default` = VoiceSelection()

    enum CodingKeys: String, CodingKey { case voiceID, voiceName, packID, speed }

    /// PIN: a selection saved by the ElevenLabs build (`modelID`, `settings`) names a voice no pack
    /// has; it reads as that name in the default pack, and the voice step falls back to the pack's
    /// first voice and says so.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voiceID = (try? c.decode(String.self, forKey: .voiceID)) ?? Self.defaultVoice
        voiceName = (try? c.decode(String.self, forKey: .voiceName)) ?? voiceID
        packID = (try? c.decode(String.self, forKey: .packID)) ?? Self.defaultPack
        speed = (try? c.decode(Double.self, forKey: .speed)) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(voiceID, forKey: .voiceID); try c.encode(voiceName, forKey: .voiceName)
        try c.encode(packID, forKey: .packID); try c.encode(speed, forKey: .speed)
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
    /// The writer shortened it because the first take ran past its window.
    public var shortened: Bool
    /// Text, voice, pack, language and speed: a clip with the same key is reused.
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
    public var packID: String
    public var lines: [NarrationLine]
    public var generatedAt: Date
    /// For a translation: the English text it was made from, so a changed English marks it stale.
    public var translatedFrom: [String]?

    public init(language: Language, voiceID: String, packID: String, lines: [NarrationLine], generatedAt: Date = Date(), translatedFrom: [String]? = nil) {
        self.language = language; self.voiceID = voiceID; self.packID = packID; self.lines = lines
        self.generatedAt = generatedAt; self.translatedFrom = translatedFrom
    }

    enum CodingKeys: String, CodingKey { case language, voiceID, packID, lines, generatedAt, translatedFrom }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decode(Language.self, forKey: .language)
        voiceID = (try? c.decode(String.self, forKey: .voiceID)) ?? VoiceSelection.defaultVoice
        packID = (try? c.decode(String.self, forKey: .packID)) ?? ""
        lines = (try? c.decode([NarrationLine].self, forKey: .lines)) ?? []
        generatedAt = (try? c.decode(Date.self, forKey: .generatedAt)) ?? Date()
        translatedFrom = try? c.decode([String].self, forKey: .translatedFrom)
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
    public var packID: String
    public var speed: Double
    public var english: VoiceTrack
    public var languages: [VoiceTrack]
    /// Set when the person has listened to the English and said it is right; cleared when the
    /// English changes. Languages are made only after it.
    public var confirmedAt: Date?
    public var appliedAt: Date

    public init(selection: VoiceSelection, english: VoiceTrack, languages: [VoiceTrack] = [], confirmedAt: Date? = nil, appliedAt: Date = Date()) {
        voiceID = selection.voiceID; voiceName = selection.voiceName; packID = selection.packID; speed = selection.speed
        self.english = english; self.languages = languages; self.confirmedAt = confirmedAt; self.appliedAt = appliedAt
    }

    enum CodingKeys: String, CodingKey { case voiceID, voiceName, packID, speed, english, languages, confirmedAt, appliedAt }

    /// PIN: a voice-over made by the ElevenLabs build has no `packID`; it reads with an empty one,
    /// so its clips play and are kept, and the next voice step speaks it again on this Mac.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voiceID = try c.decode(String.self, forKey: .voiceID)
        voiceName = (try? c.decode(String.self, forKey: .voiceName)) ?? voiceID
        packID = (try? c.decode(String.self, forKey: .packID)) ?? ""
        speed = (try? c.decode(Double.self, forKey: .speed)) ?? 1
        english = try c.decode(VoiceTrack.self, forKey: .english)
        languages = (try? c.decode([VoiceTrack].self, forKey: .languages)) ?? []
        confirmedAt = try? c.decode(Date.self, forKey: .confirmedAt)
        appliedAt = (try? c.decode(Date.self, forKey: .appliedAt)) ?? Date()
    }

    public var selection: VoiceSelection { VoiceSelection(voiceID: voiceID, voiceName: voiceName, packID: packID, speed: speed) }
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

/// What a run spoke.
public struct VoiceUsage: Codable, Sendable, Equatable, Hashable {
    public var characters: Int
    /// Lines spoken (a clip reused is not counted).
    public var requests: Int
    /// Seconds of speech made.
    public var seconds: Double
    public var packID: String

    public init(characters: Int = 0, requests: Int = 0, seconds: Double = 0, packID: String = "") {
        self.characters = characters; self.requests = requests; self.seconds = seconds; self.packID = packID
    }

    enum CodingKeys: String, CodingKey { case characters, requests, seconds, packID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        characters = (try? c.decode(Int.self, forKey: .characters)) ?? 0
        requests = (try? c.decode(Int.self, forKey: .requests)) ?? 0
        seconds = (try? c.decode(Double.self, forKey: .seconds)) ?? 0
        packID = (try? c.decode(String.self, forKey: .packID)) ?? ""
    }

    public static func + (a: VoiceUsage, b: VoiceUsage) -> VoiceUsage {
        VoiceUsage(characters: a.characters + b.characters, requests: a.requests + b.requests, seconds: a.seconds + b.seconds,
                   packID: b.packID.isEmpty ? a.packID : b.packID)
    }

    public var isEmpty: Bool { characters == 0 && requests == 0 }

    public var line: String {
        String(format: "%d %@, %.1f s of speech, %@ characters", requests, requests == 1 ? "line" : "lines", seconds, characters.formatted())
    }
}

extension Campaign {
    /// Days built without a voice-over: what switching narration on can catch up.
    public var silentBuiltDays: [Int] {
        days.filter { $0.asset.map { !$0.renders.isEmpty && $0.voiceOver == nil } ?? false }.map(\.index)
    }

    public var isNarrated: Bool { brief.voiceOver != nil }
}
