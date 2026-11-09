//
//  KokoroEngine.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: On-device TTS: the Kokoro front end (phonemes, pieces, seams) over
//        one of two acoustic halves — Kokoro-82M (FluidAudio Core ML, style
//        vectors, fixed windows) or an 8M Paradee-family student
//        (ParadeeBackend: two stages, no style vectors, any length).
//  IN:   KokoroStreamSpeaker / speak()
//  OUT:  waveform (KokoroEngine+Render: phonemes with punctuation, pieces,
//        seams) → playback
//  PIN:  Injectable actor (not MainActor singleton); macOS-only.
//  PIN:  The phoneme ids are the same for both halves (Kokoro-82M's vocab), so
//        everything above the model call is shared.
//

import Foundation
import AVFoundation
@preconcurrency import CoreML
import Accelerate

// MARK: - KokoroEngine

public actor KokoroEngine {

    public internal(set) var isLoaded  = false
    public internal(set) var isSpeaking = false

    struct LoadedModel {
        let variant: TTSVariant
        let model:   MLModel
    }
    /// All loaded models, sorted by maxTokens ascending (smallest first).
    var loadedModels: [LoadedModel] = []
    /// The student, when the directory holds one; then `loadedModels` is empty.
    var paradee: ParadeeBackend?
    /// Its voice: the name, and the row of its style table when it has one.
    var paradeeVoice: (name: String, index: Int32?)?
    /// Fixed noise for a reproducible render (the probe's `--seed`); nil draws fresh noise per call.
    var noiseSeed: UInt64?
    /// ADVERB: the student's pace (1 is its own); Kokoro-82M's windows take none.
    var speed: Float = 1
    /// Calls made with the fixed seed, so pieces of one render differ from each other.
    var noiseCalls: UInt64 = 0
    /// Sample rate of the most recently used model — kept in sync by synthesizeWaveform.
    public internal(set) var sampleRate: Double = 24_000

    let phonemizer = KokoroPhonemizer()
    let g2p        = KokoroG2P()
    var currentVoice: KokoroVoice?

    // Neutral and styled playback share engine/player. postProcessor == nil → neutral.
    var effectsEngine: AVAudioEngine?
    var effectsPlayer: AVAudioPlayerNode?
    var postProcessor: KokoroAudioProcessor?

    var configChangeObserver: NSObjectProtocol?

    /// Where models were loaded from — G2P validation reloads.
    var modelsDirectory: URL?

    /// Trace of the most recent synthesis.
    public internal(set) var lastPronunciationReport: PronunciationReport?
    var pronunciationContinuations: [UUID: AsyncStream<PronunciationReport>.Continuation] = [:]
    /// Built on the first name-help request; the lexicon never changes after load.
    var soundAlikeIndex: NameSoundAlikes.Index?

    /// What the voice does around the model call. `.legacy` is the voice as
    /// it shipped before 2026-09-28 (KokoroLegacySynthesizer keeps it).
    public internal(set) var options: KokoroOptions = .standard
    /// One gain for the loaded voice (KokoroSeamDSP.gain), set by warmUp; nil
    /// until then, when the typical peak stands in.
    var voiceGain: Float?
    /// One chunk renders at a time (KokoroEngine+Render.withGate).
    var gateBusy = false
    var gateWaiters: [CheckedContinuation<Void, Never>] = []
    /// Each chunk's synthesis report, for the probe.
    var onDiagnostics: (@Sendable (KokoroSynthesisDiagnostics) -> Void)?

    public init() {
        // Rebuild effects engine on hardware-rate change. Registered lazily on first load.
    }

    deinit {
        if let configChangeObserver {
            NotificationCenter.default.removeObserver(configChangeObserver)
        }
    }

    func observeConfigurationChangesIfNeeded() {
        guard configChangeObserver == nil else { return }
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.teardownEffectsEngine() }
        }
    }

}
