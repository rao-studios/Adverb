//
//  SpeechSynthesizer.swift
//  AdverbCore
//
//  WHAT: The seam the voice-over is spoken through: a voice pack on this Mac (Kokoro), its voices
//        and languages, and one line of text in, the samples and when each word is said out.
//  PIN:  Nothing here names Core ML. AdverbVoice implements it (KokoroSynthesizer). Word times
//        are relative to the clip; `exactTiming` says they came from the model's own durations
//        rather than an even split of the voiced span (VoiceSync and the captions take either).
//  PIN:  Languages are a pack's to say. English is the only one spoken today; a pack for another
//        language adds itself without the agents changing (VoiceJob asks `supports`).
//

import Foundation

public struct SpeechVoice: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// The pack's own name for it ("af_heart").
    public var id: String
    /// "Heart".
    public var name: String
    public var packID: String
    public var language: Language
    /// "American", "British".
    public var accent: String
    /// "female", "male".
    public var gender: String
    public var note: String

    public init(id: String, name: String, packID: String, language: Language = .english, accent: String = "American",
                gender: String = "", note: String = "") {
        self.id = id; self.name = name; self.packID = packID; self.language = language; self.accent = accent
        self.gender = gender; self.note = note
    }

    /// "Heart · American female".
    public var summary: String { [name, [accent, gender].filter { !$0.isEmpty }.joined(separator: " ")].filter { !$0.isEmpty }.joined(separator: " · ") }
}

/// A voice pack: the model that speaks, its voices, the languages its front end reads.
public struct SpeechPackInfo: Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var revision: String?
    public var voices: [SpeechVoice]
    public var languages: [Language]
    /// Word times come from the model's own durations.
    public var exactTiming: Bool
    /// It can speak faster on request (a line that runs long is spoken again at up to 1.15×).
    public var adjustsSpeed: Bool

    public init(id: String, title: String, revision: String? = nil, voices: [SpeechVoice], languages: [Language] = [.english],
                exactTiming: Bool, adjustsSpeed: Bool) {
        self.id = id; self.title = title; self.revision = revision; self.voices = voices; self.languages = languages
        self.exactTiming = exactTiming; self.adjustsSpeed = adjustsSpeed
    }

    public func supports(_ language: Language) -> Bool { languages.contains(language) }
    public func voice(_ id: String) -> SpeechVoice? { voices.first { $0.id == id } }
}

public struct SpeechRequest: Sendable, Equatable {
    public var text: String
    public var voiceID: String
    public var language: Language
    /// 1 is the voice's own pace.
    public var speed: Double
    /// A fixed seed makes the same words the same audio, so a clip made again is the clip it was.
    public var seed: UInt64?

    public init(text: String, voiceID: String, language: Language = .english, speed: Double = 1, seed: UInt64? = 7) {
        self.text = text; self.voiceID = voiceID; self.language = language; self.speed = speed; self.seed = seed
    }
}

public struct SpeechClip: Sendable, Equatable {
    /// Mono Float32.
    public var samples: [Float]
    public var sampleRate: Double
    /// Each word of the line, in the line's own order, relative to the clip.
    public var words: [WordTiming]
    /// When the voice starts and stops within the clip.
    public var spokenStart: Double
    public var spokenEnd: Double
    public var exactTiming: Bool

    public init(samples: [Float], sampleRate: Double, words: [WordTiming], spokenStart: Double, spokenEnd: Double, exactTiming: Bool) {
        self.samples = samples; self.sampleRate = sampleRate; self.words = words; self.spokenStart = spokenStart
        self.spokenEnd = spokenEnd; self.exactTiming = exactTiming
    }

    public var seconds: Double { sampleRate > 0 ? Double(samples.count) / sampleRate : 0 }
}

/// One loaded voice pack.
public protocol SpeechSynthesizer: Sendable {
    var pack: SpeechPackInfo { get }
    func speak(_ request: SpeechRequest) async throws -> SpeechClip
}

/// The voice packs on this Mac, each loaded when first spoken with.
public protocol SpeechProvider: Sendable {
    /// Installed packs.
    var packs: [SpeechPackInfo] { get }
    func synthesizer(pack: String) async throws -> any SpeechSynthesizer
}

extension SpeechProvider {
    public var voices: [SpeechVoice] { packs.flatMap(\.voices) }
    public func pack(_ id: String) -> SpeechPackInfo? { packs.first { $0.id == id } }

    /// The pack and voice a selection names, else the first installed pack's first voice.
    public func resolve(_ selection: VoiceSelection) -> (pack: SpeechPackInfo, voice: SpeechVoice)? {
        if let pack = pack(selection.packID), let voice = pack.voice(selection.voiceID) { return (pack, voice) }
        for pack in packs { if let voice = pack.voice(selection.voiceID) { return (pack, voice) } }
        guard let pack = packs.first, let voice = pack.voices.first else { return nil }
        return (pack, voice)
    }
}

public enum SpeechError: Error, Equatable, CustomStringConvertible {
    case noPack
    case packMissing(String)
    case unsupportedLanguage(Language)
    case failed(String)

    public var description: String {
        switch self {
        case .noPack: "No voice is on this Mac. Download one in Settings › Voice."
        case .packMissing(let id): "The voice pack \(id) is not on this Mac. Download it in Settings › Voice."
        case .unsupportedLanguage(let l): "No voice on this Mac speaks \(l.title) yet."
        case .failed(let why): "The voice failed: \(why)"
        }
    }
}
