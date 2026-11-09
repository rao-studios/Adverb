//
//  KokoroEngine+LoadingAndSelection.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: Load models, pick variant, seed proper-noun IPA.
//  IN:   KokoroEngine.swift (same actor)
//  OUT:  loadedModels / phonemizer / g2p
//

import Foundation
import AVFoundation
@preconcurrency import CoreML
import Accelerate

extension KokoroEngine {

    // MARK: - Loading

    /// Load models from the kokoro resource directory.
    /// Layout: kokoro_*.mlmodelc or ParadeeText/ParadeeAcoustic.mlmodelc, vocab_index.json,
    /// us_gold.json, us_silver.json?, voices/*.json (Kokoro only)
    /// Empty `variants` = auto-discover every present model. Synthesis picks the smallest fit.
    /// - Parameter acousticDirectory: a student's models from elsewhere (the probe's
    ///   `--model-dir`); the front end still loads from `modelsDir`. A student in
    ///   `modelsDir` itself is found without it. `variants` names Kokoro windows and is
    ///   ignored when a student loads.
    public func loadModels(
        from modelsDir: URL,
        variants: [String] = [],
        computeUnits: MLComputeUnits = .cpuAndNeuralEngine,
        acousticDirectory: URL? = nil
    ) async throws {
        observeConfigurationChangesIfNeeded()
        modelsDirectory = modelsDir

        if let studentDir = acousticDirectory ?? (ParadeeBackend.isPresent(in: modelsDir) ? modelsDir : nil) {
            let backend = try await ParadeeBackend.load(from: studentDir) { try await self.compileIfNeeded($0) }
            paradee = backend
            loadedModels = []
            sampleRate = backend.sampleRate
            print("✅ Paradee — \(backend.voices.joined(separator: ", ")) from \(studentDir.lastPathComponent), ≤\(backend.maxTokens) ids")
            try loadFrontEnd(from: modelsDir, computeUnits: computeUnits)
            await loadG2PIfAvailable(in: modelsDir, computeUnits: computeUnits)
            seedBuiltInProperNouns()
            isLoaded = true
            return
        }
        paradee = nil

        // Resolve the set of variants to attempt — explicit list or every known variant.
        let names = variants.isEmpty
            ? TTSConfig.variants.map(\.name)
            : variants

        let cfg = MLModelConfiguration()
        cfg.computeUnits = computeUnits

        var newModels: [LoadedModel] = []

        for variantName in names {
            guard let variantConfig = TTSConfig.variants.first(where: { $0.name == variantName }) else {
                print("⚠️ Unknown variant '\(variantName)' — skipping")
                continue
            }
            guard let modelURL = findModelURL(variantName, in: modelsDir) else {
                if !variants.isEmpty {
                    // Caller explicitly requested this variant — treat as error.
                    throw TTSError.modelLoadFailed("\(variantName) not found in \(modelsDir.path)")
                }
                // Auto-discovery: variant simply isn't present, skip silently.
                continue
            }

            print("📦 Loading model: \(modelURL.lastPathComponent)")
            let compiled    = try await compileIfNeeded(modelURL)
            let loadedModel = try MLModel(contentsOf: compiled, configuration: cfg)

            // Read actual shapes from model metadata — overrides hardcoded config values.
            // (e.g. kokoro_21_10s uses 249 tokens, not 242)
            let desc = loadedModel.modelDescription
            var resolvedTokens  = variantConfig.maxTokens
            var resolvedSamples = variantConfig.maxSamples
            if let tokenShape = desc.inputDescriptionsByName["input_ids"]?.multiArrayConstraint?.shape,
               tokenShape.count >= 2 {
                resolvedTokens = tokenShape[1].intValue
            }
            if let audioShape = desc.outputDescriptionsByName["audio"]?.multiArrayConstraint?.shape,
               audioShape.count >= 3 {
                resolvedSamples = audioShape[2].intValue
            }

            // Build a resolved variant reflecting the model's actual I/O shapes.
            let resolved = TTSVariant(
                name:       variantConfig.name,
                sampleRate: variantConfig.sampleRate,
                maxTokens:  resolvedTokens,
                maxSamples: resolvedSamples
            )
            print("✅ \(variantName) — maxTokens: \(resolvedTokens), maxSamples: \(resolvedSamples), sampleRate: \(variantConfig.sampleRate)")
            newModels.append(LoadedModel(variant: resolved, model: loadedModel))
        }

        guard !newModels.isEmpty else {
            throw TTSError.modelLoadFailed("No model files found in \(modelsDir.path)")
        }

        // Sort ascending by audio window so selectModel() can do a simple
        // first-match scan (the exported variants share a 242-token window
        // and differ in how many seconds of audio they can emit).
        loadedModels = newModels.sorted { $0.variant.maxSamples < $1.variant.maxSamples }
        // Expose the largest model's sample rate as the default (updated per-synthesis call).
        sampleRate = loadedModels.last!.variant.sampleRate

        try loadFrontEnd(from: modelsDir, computeUnits: computeUnits)

        // Load G2P model (optional — silently skipped if files are absent).
        await loadG2PIfAvailable(in: modelsDir, computeUnits: computeUnits)

        // Seed known proper-noun pronunciations that the English lexicon omits.
        seedBuiltInProperNouns()

        isLoaded = true
    }

    /// The phoneme vocabulary and lexicons — the same for either acoustic half.
    func loadFrontEnd(from modelsDir: URL, computeUnits: MLComputeUnits) throws {
        let vocabURL = modelsDir.appendingPathComponent("vocab_index.json")
        try phonemizer.loadVocab(from: vocabURL)

        for name in ["us_gold.json", "gb_gold.json", "us_silver.json", "gb_silver.json"] {
            let url = modelsDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try phonemizer.loadLexicon(from: url)
            }
        }
    }

    /// Ids one model call takes, the two zeros included.
    var maxTokensPerCall: Int {
        paradee?.maxTokens ?? loadedModels.last?.variant.maxTokens ?? 242
    }

    /// A voice is loaded for whichever half is.
    var hasVoice: Bool { paradee != nil ? paradeeVoice != nil : currentVoice != nil }

    /// The loaded voice's name.
    public var voiceName: String? { paradee != nil ? paradeeVoice?.name : currentVoice?.name }

    func loadG2PIfAvailable(in modelsDir: URL, computeUnits: MLComputeUnits) async {
        let vocabURL  = modelsDir.appendingPathComponent("g2p_vocab.json")
        let cacheURL  = modelsDir.appendingPathComponent("us_lexicon_cache.json")

        // Use findModelURL so both .mlpackage and compiled .mlmodelc are found.
        guard let encoderURL = findModelURL("G2PEncoder", in: modelsDir),
              let decoderURL = findModelURL("G2PDecoder", in: modelsDir),
              FileManager.default.fileExists(atPath: vocabURL.path) else {
            print("ℹ️ G2P models not found — skipping")
            return
        }

        do {
            try g2p.loadVocab(from: vocabURL)

            if FileManager.default.fileExists(atPath: cacheURL.path) {
                try await g2p.loadLexiconCache(from: cacheURL)
            }

            try await g2p.loadModels(encoderURL: encoderURL, decoderURL: decoderURL,
                                     computeUnits: computeUnits)
            phonemizer.g2p = g2p
            print("✅ G2P pipeline active")
        } catch {
            print("⚠️ G2P load failed (continuing without it): \(error)")
        }
    }

    // MARK: - Model selection

    /// ≈17 phoneme tokens/s — selection honors both token window and estimated duration.
    static let phonemeTokensPerSecond: Double = 17

    /// Returns the smallest loaded model that fits `tokenCount` in its token
    /// window AND its audio window (estimated). Falls back to the largest.
    func selectModel(for tokenCount: Int) -> LoadedModel? {
        let estimatedSeconds = Double(tokenCount) / Self.phonemeTokensPerSecond
        return loadedModels.first {
            $0.variant.maxTokens >= tokenCount
                && Double($0.variant.maxSamples) / $0.variant.sampleRate >= estimatedSeconds
        } ?? loadedModels.last
    }

    /// IPA for proper nouns the gold lexicons omit. PIN: never seed her name —
    /// it is the user's (Settings → Name → Pronunciation help saves it as a
    /// custom pronunciation), and a rename would leave a seeded IPA speaking.
    func seedBuiltInProperNouns() {
        // User's name, as pronounced. Possessives compose via morphology.
        phonemizer.addCustomPronunciation("Ritesh", ipa: "ɹɛtˈɛʃ")
        phonemizer.addCustomPronunciation("Pakala", ipa: "pˈɑkɑlɑ")
        phonemizer.addCustomPronunciation("Rao", ipa: "ɹˈW")
        // Kept from the source port as a worked example of the override mechanism.
        phonemizer.addCustomPronunciation("Marielle", ipa: "mɑːriɛl")
    }

    /// IPA override for this engine instance. Same character set as the loaded vocab.
    public func addCustomPronunciation(_ word: String, ipa: String) {
        phonemizer.addCustomPronunciation(word, ipa: ipa)
    }

    /// `modelsDir` is Kokoro's `voices/`; a student's voices are its own, by name.
    public func loadVoice(named name: String, in modelsDir: URL) throws {
        if let paradee {
            let index = paradee.voiceIndex(for: name)
            guard paradee.voices.contains(name), !paradee.takesVoice || index != nil else {
                throw TTSError.invalidVoiceFile(name)
            }
            paradeeVoice = (name, index)
            voiceGain = nil
            print("🎙️ Voice loaded: \(name)")
            return
        }
        currentVoice = try KokoroVoice.load(named: name, in: modelsDir)
        voiceGain = nil  // another voice, another level: warmUp measures it again
        print("🎙️ Voice loaded: \(currentVoice!.name)")
    }

    /// The probe's `--seed`: every render after it draws the same noise in the same order.
    public func setNoiseSeed(_ seed: UInt64?) {
        noiseSeed = seed
        noiseCalls = 0
    }

    // MARK: - Warm-up

    /// Sentences the voice is measured on: a greeting, a statement, a clause-y one.
    static let calibrationSentences = [
        "Hi! It's good to hear from you, and I'm glad you asked.",
        "That sounds like a lovely way to spend a quiet evening at home.",
        "Here's the thing: it depends on what you want, and when you need it.",
    ]

    /// The first real calls, before anyone is waiting: every window's first
    /// prediction and the G2P are paid here, and the loaded voice's loudness
    /// sets its gain. Idempotent per voice; a later loadVoice runs it again.
    public func warmUp() async {
        if paradee != nil {
            await warmUpParadee()
            return
        }
        guard isLoaded, voiceGain == nil, let voice = currentVoice else { return }
        let started = Date()
        let calibrated: Float? = try? await withGate {
            // Another warm-up may have measured, or the voice changed, while this one queued.
            guard voiceGain == nil, currentVoice === voice else { return nil }
            var loudness: [Float] = []
            for (index, text) in Self.calibrationSentences.enumerated() {
                let phonemes = await phonemizer.phonemizeUnits(text, options: options)
                let ids = [0] + phonemes.ids(0..<phonemes.units.count, closeWith: ".") + [0]
                guard let embedding = voice.embedding(for: ids.count - 2, style: options.styleVector) else { continue }
                // The first sentence goes through every window; the others through the one they'd use.
                let models = index == 0 ? loadedModels : selectModel(for: ids.count).map { [$0] } ?? []
                for model in models {
                    let output = try await runModel(ids: ids, embedding: embedding, model: model)
                    let level = KokoroSeamDSP.voicedLoudness(output.samples, sampleRate: model.variant.sampleRate)
                    if level.isFinite { loudness.append(level) }
                }
            }
            guard !loudness.isEmpty else { return nil }
            return loudness.sorted()[loudness.count / 2]
        }
        // A voice loaded meanwhile is not this voice: its own warm-up measures it.
        guard voiceGain == nil, currentVoice === voice, let calibrated else { return }
        voiceGain = KokoroSeamDSP.gain(loudnessDb: calibrated)
        print(String(format: "🔥 Kokoro warm in %.1fs — %@ at %.1f dBFS, gain %.2f",
                     Date().timeIntervalSince(started), voice.name, calibrated, voiceGain ?? 1))
    }

    /// The student's calibration: the same sentences, the same median, its own level.
    private func warmUpParadee() async {
        guard isLoaded, voiceGain == nil, let voice = paradeeVoice, let backend = paradee else { return }
        let started = Date()
        let calibrated: Float? = try? await withGate {
            guard voiceGain == nil, paradeeVoice?.name == voice.name else { return nil }
            var loudness: [Float] = []
            for text in Self.calibrationSentences {
                let phonemes = await phonemizer.phonemizeUnits(text, options: options)
                let ids = [0] + phonemes.ids(0..<phonemes.units.count, closeWith: ".") + [0]
                let output = try await backend.run(ids: ids, voice: voice.index, seed: nextNoiseSeed())
                let level = KokoroSeamDSP.voicedLoudness(output.samples, sampleRate: backend.sampleRate)
                if level.isFinite { loudness.append(level) }
            }
            guard !loudness.isEmpty else { return nil }
            return loudness.sorted()[loudness.count / 2]
        }
        guard voiceGain == nil, paradeeVoice?.name == voice.name, let calibrated else { return }
        voiceGain = KokoroSeamDSP.gain(loudnessDb: calibrated)
        print(String(format: "🔥 Paradee warm in %.1fs — %@ at %.1f dBFS, gain %.2f",
                     Date().timeIntervalSince(started), voice.name, calibrated, voiceGain ?? 1))
    }

    /// The seed for the next student call: fixed and counted under `--seed`, fresh otherwise.
    func nextNoiseSeed() -> UInt64 {
        guard let noiseSeed else { return UInt64.random(in: .min ... .max) }
        defer { noiseCalls &+= 1 }
        return noiseSeed &+ noiseCalls &* 0x9E37_79B9
    }

    /// Voice names available: a student's own list, else `<modelsDir>/voices/`.
    public nonisolated static func availableVoices(in modelsDir: URL) -> [String] {
        if ParadeeBackend.isPresent(in: modelsDir) { return ParadeeBackend.voices(in: modelsDir) }
        let voicesDir = modelsDir.appendingPathComponent("voices")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: voicesDir.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }

}
