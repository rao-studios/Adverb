//
//  KokoroOptions.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: What the on-device voice does around the model call, one switch per
//        piece, so a render can put each against what shipped before it.
//  IN:   KokoroEngine.options (the app), the probe's --legacy / --options
//  OUT:  KokoroPhonemizer (punctuation, function words), KokoroEngine+Render
//        (segments, style vector, seams)
//  PIN:  `.legacy` is byte for byte the voice before these switches existed,
//        kept for the probe's A/B. Since 2026-10-31 nothing in the app speaks
//        it: the hosted voice's cover runs on the standard render, so a
//        covered chunk has the same seams and level as every other.
//

public struct KokoroOptions: Sendable, Equatable {

    /// Punctuation reaches the model as its own tokens, where the text has it
    /// (misaki-style). Kokoro learned its pauses and intonation from those
    /// tokens. Off keeps only a chunk's final `. ! ? ,`.
    public var punctuation: Bool
    /// "the / a / an / to / in / am / I" said as the model was trained to hear
    /// them: "ðə cat", "ði owl", "ɐ mat", "tə go".
    public var contextualFunctionWords: Bool
    /// Text past the model's window is split at its best boundary and spoken
    /// in pieces. Off drops everything past the window.
    public var segments: Bool
    /// Which style vector conditions the voice.
    public var styleVector: StyleVector
    /// One gain per voice, edges trimmed and faded, designed pauses between
    /// pieces. Off peak-normalizes every chunk to full scale on its own.
    public var seams: Bool

    public enum StyleVector: Sendable, Equatable {
        /// The voice file's mean vector, whatever the length.
        case mean
        /// The vector for this many phonemes, as upstream Kokoro picks it;
        /// counts under `floor` use `floor`'s.
        case lengthIndexed(floor: Int)
    }

    public init(
        punctuation: Bool, contextualFunctionWords: Bool, segments: Bool,
        styleVector: StyleVector, seams: Bool
    ) {
        self.punctuation = punctuation
        self.contextualFunctionWords = contextualFunctionWords
        self.segments = segments
        self.styleVector = styleVector
        self.seams = seams
    }

    /// The voice as it shipped before 2026-09-28.
    public static let legacy = KokoroOptions(
        punctuation: false, contextualFunctionWords: false, segments: false,
        styleVector: .mean, seams: false)

    /// What the app speaks with.
    public static let standard = KokoroOptions(
        punctuation: true, contextualFunctionWords: true, segments: true,
        styleVector: .mean, seams: true)
}
