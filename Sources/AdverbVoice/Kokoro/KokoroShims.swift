//
//  KokoroShims.swift
//  AdverbVoice
//
//  WHAT: What the lifted Kokoro engine named from the rest of AmbientVoice: its one chunk result
//        (SynthesizedChunk, from TTS/Shared/SpeechSynthesizer.swift) and its strings helper, here
//        plain English (Adverb's UI is English; its errors are logged and shown as they are).
//  PIN:  Ambient's own `SpeechSynthesizer` protocol is not lifted: AdverbCore's has the name, and
//        KokoroSynthesizer is what adopts it here.
//

import Foundation

/// One chunk's complete result, carried together — prefetch-safe (no shared rate race).
public struct SynthesizedChunk: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let pronunciation: PronunciationReport?
    /// Each spoken word's span in `samples`, when the acoustic half reports durations (Paradee).
    public var wordSpans: [KokoroWordSpan] = []

    public init(samples: [Float], sampleRate: Double, pronunciation: PronunciationReport?, wordSpans: [KokoroWordSpan] = []) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.pronunciation = pronunciation
        self.wordSpans = wordSpans
    }
}

/// A word as the engine said it: its text and where its sound sits in the chunk, in seconds.
public struct KokoroWordSpan: Sendable, Equatable {
    public var text: String
    public var start: Double
    public var end: Double
    public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
}

enum VoiceStrings {
    static func ui(_ text: String) -> String { text }
}

/// The token folding NameSoundAlikes uses (Ambient's WakePlanner.tokens over SpokenTokenFolding).
enum WakePlanner {
    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { String($0).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .lowercased().filter { $0.isLetter || $0.isNumber } }
            .filter { !$0.isEmpty }
    }
}
