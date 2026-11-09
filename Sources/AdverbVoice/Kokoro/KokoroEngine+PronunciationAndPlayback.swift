//
//  KokoroEngine+PronunciationAndPlayback.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: Pronunciation traces + simple/styled playback.
//  IN:   KokoroEngine.swift (same actor)
//  OUT:  PronunciationReport / AVAudioEngine
//

import Foundation
import AVFoundation
@preconcurrency import CoreML
import Accelerate

extension KokoroEngine {

    // MARK: - Pronunciation inspection

    /// A fresh stream of per-synthesis pronunciation traces for each subscriber.
    public func pronunciationEvents() -> AsyncStream<PronunciationReport> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<PronunciationReport>.makeStream(bufferingPolicy: .unbounded)
        pronunciationContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removePronunciationContinuation(id) }
        }
        return stream
    }

    func removePronunciationContinuation(_ id: UUID) {
        pronunciationContinuations[id] = nil
    }

    /// Trace how `text` would be pronounced — no synthesis, no audio.
    public func pronunciationReport(for text: String) async throws -> PronunciationReport {
        guard isLoaded else { throw TTSError.modelsNotLoaded }
        return await phonemizer.phonemize(text, maxTokens: maxTokensPerCall, options: options).report
    }

    // MARK: - Name help

    /// How each word of `name` would be spoken, plus spellings a recognizer may
    /// write for it. Local; nothing is stored.
    public func nameHelp(for name: String) async throws -> NamePronunciationHelp {
        guard isLoaded else { throw TTSError.modelsNotLoaded }
        var words: [NamePronunciationHelp.Word] = []
        for word in name.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            let entry = await phonemizer.pronounce(word)
            words.append(.init(word: word, ipa: entry.ipa, source: entry.source))
        }
        // Spelled-out or salvaged sounds are letters, not the name.
        let trusted: Set<PronunciationSource> =
            [.ssml, .custom, .lexicon, .lexiconVariant, .cache, .morphology, .g2p]
        let tokens = words.map {
            NameSoundAlikes.Token(word: $0.word, ipa: trusted.contains($0.source) ? $0.ipa : "")
        }
        // Index build (~1 s once) and the scan run off the actor, so speech
        // queued meanwhile is not held up.
        let cached = soundAlikeIndex
        let lexicon = cached == nil ? phonemizer.lexiconEntries : [:]
        let (index, heardAs) = await Task.detached(priority: .userInitiated) {
            let index = cached ?? NameSoundAlikes.Index(lexicon: lexicon)
            return (index, NameSoundAlikes.suggest(name: name, tokens: tokens, index: index))
        }.value
        if soundAlikeIndex == nil { soundAlikeIndex = index }
        return NamePronunciationHelp(name: name, words: words, heardAs: heardAs)
    }

    /// Speak `name` with explicit IPA per word — the Settings "Play". Words
    /// without an entry use the normal ladder.
    public func previewName(_ name: String, ipaByWord: [String: String]) async throws {
        let text = name.split(whereSeparator: { $0.isWhitespace }).map { part -> String in
            let word = String(part)
            guard let ipa = ipaByWord[word], !ipa.isEmpty, !ipa.contains("\"") else { return word }
            return "<phoneme alphabet=\"ipa\" ph=\"\(ipa)\">\(word)</phoneme>"
        }.joined(separator: " ")
        try await speak(text)
    }

    /// Score the neural G2P against ground-truth cache pairs. With
    /// `tryAllConfigs`, runs the full A/B matrix: start token (pad vs bos) ×
    /// encoder padding × compute units.
    public func validateG2P(
        sampleCount: Int = 500,
        seed: UInt64 = 42
    ) async -> [String] {
        guard g2p.isLoaded else { return ["G2P models are not loaded."] }
        let pairs = g2p.sampleCachePairs(count: sampleCount, seed: seed)
        guard !pairs.isEmpty else { return ["G2P cache is empty — nothing to validate against."] }

        let result = await g2p.validate(pairs: pairs)
        var summaries = [result.summary]
        for (word, expected, got) in result.worst where expected != got {
            summaries.append("    worst: '\(word)' expected '\(expected)' got '\(got)'")
        }
        return summaries
    }

    func reloadG2P(in modelsDir: URL, computeUnits: MLComputeUnits) async throws {
        guard let encoderURL = findModelURL("G2PEncoder", in: modelsDir),
              let decoderURL = findModelURL("G2PDecoder", in: modelsDir) else {
            throw TTSError.modelLoadFailed("G2P models not found")
        }
        try await g2p.loadModels(encoderURL: encoderURL, decoderURL: decoderURL,
                                 computeUnits: computeUnits)
    }

    public func stop() {
        effectsPlayer?.stop()
        effectsEngine?.stop()
        isSpeaking = false
    }

    func teardownEffectsEngine() {
        effectsPlayer?.stop()
        effectsEngine?.stop()
        effectsEngine = nil
        effectsPlayer = nil
        postProcessor = nil
    }

    // MARK: - Simple playback (neutral — AVAudioPlayerNode with raw Float32 PCM,
    // no WAV encode/decode and no Int16 quantization)

    func playSimple(_ waveform: [Float]) async throws {
        let hwRate = Self.hardwareSampleRate()
        let resampled = sampleRate != hwRate
            ? try Self.resample(waveform, from: sampleRate, to: hwRate)
            : waveform

        let fmt = AVAudioFormat(standardFormatWithSampleRate: hwRate, channels: 1)!
        let buf = try pcmBuffer(from: resampled, sampleRate: hwRate)

        // Reuse or build a minimal engine — player → mainMixer → output,
        // no processing nodes, hardware-rate format throughout.
        let needsRebuild = effectsEngine == nil
            || effectsEngine!.outputNode.outputFormat(forBus: 0).sampleRate != hwRate

        let engine: AVAudioEngine
        let player: AVAudioPlayerNode

        if !needsRebuild, let e = effectsEngine, let p = effectsPlayer, postProcessor == nil {
            engine = e; player = p
        } else {
            teardownEffectsEngine()
            engine = AVAudioEngine()
            player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: fmt)
            self.effectsEngine = engine
            self.effectsPlayer = player
            // postProcessor intentionally nil — this is the neutral path
        }

        if !engine.isRunning { try engine.start() }
        player.play()

        isSpeaking = true
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(buf) { c.resume() }
        }
        player.stop()
        isSpeaking = false
    }

    // MARK: - Styled playback (non-neutral — AVAudioEngine at hardware rate)

    func playStyled(_ waveform: [Float], style: TTSSpeechStyle) async throws {
        let hwRate = Self.hardwareSampleRate()

        // Build engine at hardware rate so no implicit SRC occurs anywhere in the graph.
        // Tear down and rebuild if the hardware rate has changed since last use.
        let needsRebuild = effectsEngine == nil
            || effectsEngine!.outputNode.outputFormat(forBus: 0).sampleRate != hwRate

        let processor: KokoroAudioProcessor
        let engine:    AVAudioEngine
        let player:    AVAudioPlayerNode

        if !needsRebuild, let e = effectsEngine, let p = effectsPlayer, let pr = postProcessor {
            processor = pr; engine = e; player = p
        } else {
            teardownEffectsEngine()
            processor = KokoroAudioProcessor()
            engine    = AVAudioEngine()
            player    = AVAudioPlayerNode()
            // Connect graph using hardware rate — no SRC anywhere in the chain
            let fmt = AVAudioFormat(standardFormatWithSampleRate: hwRate, channels: 1)!
            engine.attach(player)
            processor.connect(player: player, to: engine, format: fmt)
            self.postProcessor = processor
            self.effectsEngine = engine
            self.effectsPlayer = player
        }

        processor.apply(style)

        if !engine.isRunning { try engine.start() }
        player.play()

        // Resample waveform to hardware rate before scheduling
        let resampled = sampleRate != hwRate
            ? try Self.resample(waveform, from: sampleRate, to: hwRate)
            : waveform
        let buf = try pcmBuffer(from: resampled, sampleRate: hwRate)

        isSpeaking = true
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(buf) { c.resume() }
        }
        player.stop()
        engine.stop()
        isSpeaking = false
    }

}
