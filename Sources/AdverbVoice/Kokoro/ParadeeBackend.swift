//
//  ParadeeBackend.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: The 8M Kokoro students (Paradee-8M, teacher-in-the-loop) as the
//        engine's acoustic half: two Core ML stages with the duration
//        expansion on the host, the same phoneme ids Kokoro takes.
//  IN:   KokoroEngine.loadModels (a directory holding ParadeeText /
//        ParadeeAcoustic and paradee.json or config.json)
//  OUT:  24 kHz samples + per-token frame counts (KokoroModelOutput)
//
//    ParadeeText      input_ids [1,T] int32 (0 at both ends, T ≤ 512) [, voice [1]]
//                     → duration [1,T] (pre-round), d [1,C,T], asr_tok [1,512,T]
//    host             n = max(1, round(duration / speed)); en = repeat(d, n); asr = repeat(asr_tok, n)
//                     noise = N(0,1) [1,1,600F], F = Σn
//    ParadeeAcoustic  en, asr, noise [, voice] → audio [1,600F]
//
//  PIN:  CPU only. `.all` and `.cpuAndGPU` abort in MPSGraph on the LSTMs.
//  PIN:  The noise is an input, so a seeded render is the same render: the
//        probe's A/B and the tests depend on it. round() is half-to-even, as
//        torch.round is, so the frame counts match the reference exactly.
//  PIN:  A frame is 600 samples — Kokoro's pred_dur frame — so the seam trims
//        and the probe's frame columns read these durations unchanged.
//

import Foundation
@preconcurrency import CoreML

/// What the directory says about its models; voices in their table's order.
struct ParadeeManifest: Decodable, Sendable {
    var voices: [String]?
    var sampleRate: Double?
    var samplesPerFrame: Int?
    var maxFrames: Int?
    var maxPhonemes: Int?

    enum CodingKeys: String, CodingKey {
        case voices
        case sampleRate = "sample_rate"
        case samplesPerFrame = "samples_per_frame"
        case maxFrames = "max_frames"
        case maxPhonemes = "max_phonemes"
    }

    static let fileNames = ["paradee.json", "config.json"]

    static func load(in directory: URL) -> ParadeeManifest? {
        for name in fileNames {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(ParadeeManifest.self, from: data) else { continue }
            return manifest
        }
        return nil
    }
}

struct ParadeeBackend: @unchecked Sendable {
    let text: MLModel
    let acoustic: MLModel
    let directory: URL
    /// The voice table, or one unnamed voice when the models take no `voice` input.
    let voices: [String]
    let takesVoice: Bool
    let sampleRate: Double
    let samplesPerFrame: Int
    let maxFrames: Int
    /// Ids per call, the two zeros included.
    let maxTokens: Int

    static let textName = "ParadeeText"
    static let acousticName = "ParadeeAcoustic"
    /// A single-voice student's one voice, when its manifest names none.
    static let defaultVoice = "af_heart"
    /// teacher-in-the-loop af_heart's calibration sentences, raw (voicedLoudness,
    /// as warmUp measures them; 2026-10-31), until warmUp measures the loaded voice.
    static let typicalLoudnessDb: Float = -25.9

    /// True when `directory` holds both stages.
    static func isPresent(in directory: URL) -> Bool {
        [textName, acousticName].allSatisfy { name in
            ["mlmodelc", "mlpackage"].contains { ext in
                FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(name).\(ext)").path)
            }
        }
    }

    /// The voices a directory offers, without loading anything.
    static func voices(in directory: URL) -> [String] {
        let listed = ParadeeManifest.load(in: directory)?.voices ?? []
        return listed.isEmpty ? [defaultVoice] : listed
    }

    static func load(from directory: URL, compile: (URL) async throws -> URL) async throws -> ParadeeBackend {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        func model(_ name: String) async throws -> MLModel {
            let compiled = directory.appendingPathComponent("\(name).mlmodelc")
            let package = directory.appendingPathComponent("\(name).mlpackage")
            let url = FileManager.default.fileExists(atPath: compiled.path) ? compiled : try await compile(package)
            return try MLModel(contentsOf: url, configuration: configuration)
        }
        let text = try await model(textName)
        let acoustic = try await model(acousticName)
        let manifest = ParadeeManifest.load(in: directory)
        let takesVoice = text.modelDescription.inputDescriptionsByName["voice"] != nil
        let listed = manifest?.voices ?? []
        return ParadeeBackend(
            text: text, acoustic: acoustic, directory: directory,
            voices: takesVoice && !listed.isEmpty ? listed : [listed.first ?? defaultVoice],
            takesVoice: takesVoice,
            sampleRate: manifest?.sampleRate ?? 24_000,
            samplesPerFrame: manifest?.samplesPerFrame ?? 600,
            maxFrames: manifest?.maxFrames ?? 4_000,
            maxTokens: (manifest?.maxPhonemes ?? 510) + 2)
    }

    /// The voice's row, or nil for a model with one voice.
    func voiceIndex(for name: String) -> Int32? {
        guard takesVoice else { return nil }
        return voices.firstIndex(of: name).map(Int32.init)
    }

    struct Output {
        var samples: [Float]
        /// Frames per id, after rounding — what was spoken for each.
        var frames: [Float]
        var seconds: Double
    }

    /// One call: ids (zeros at both ends) to audio.
    func run(ids: [Int32], voice: Int32?, speed: Float = 1, seed: UInt64) async throws -> Output {
        let started = Date()
        let count = ids.count
        let inputIDs = try MLMultiArray(shape: [1, NSNumber(value: count)], dataType: .int32)
        let idPointer = inputIDs.dataPointer.bindMemory(to: Int32.self, capacity: count)
        for (index, id) in ids.enumerated() { idPointer[index] = id }
        var textInputs: [String: MLFeatureValue] = ["input_ids": MLFeatureValue(multiArray: inputIDs)]
        let voiceArray = try voice.map { index -> MLMultiArray in
            let array = try MLMultiArray(shape: [1], dataType: .int32)
            array[0] = NSNumber(value: index)
            return array
        }
        if let voiceArray { textInputs["voice"] = MLFeatureValue(multiArray: voiceArray) }

        try Task.checkCancellation()
        let textOut = try await text.prediction(from: try MLDictionaryFeatureProvider(dictionary: textInputs))
        guard let duration = textOut.featureValue(for: "duration")?.multiArrayValue,
              let d = textOut.featureValue(for: "d")?.multiArrayValue,
              let asrTok = textOut.featureValue(for: "asr_tok")?.multiArrayValue else {
            throw TTSError.predictionFailed("Paradee text stage: missing outputs")
        }

        // Frames per id: max(1, round(duration / speed)), half to even as torch rounds.
        var frames = [Int](repeating: 1, count: count)
        for index in 0..<count {
            let value = Self.float(duration, [0, index]) / max(speed, 0.01)
            frames[index] = max(1, Int(value.rounded(.toNearestOrEven)))
        }
        var total = frames.reduce(0, +)
        if total > maxFrames {
            // Past the acoustic window: the tail is what gives.
            var excess = total - maxFrames
            for index in stride(from: count - 1, through: 0, by: -1) where excess > 0 {
                let cut = min(excess, frames[index] - 1)
                frames[index] -= cut
                excess -= cut
            }
            total = frames.reduce(0, +)
        }

        let en = try Self.expand(d, frames: frames, total: total)
        let asr = try Self.expand(asrTok, frames: frames, total: total)
        let sampleCount = total * samplesPerFrame
        let noise = try MLMultiArray(shape: [1, 1, NSNumber(value: sampleCount)], dataType: .float32)
        var generator = SeededGaussian(seed: seed)
        let noisePointer = noise.dataPointer.bindMemory(to: Float.self, capacity: sampleCount)
        for index in 0..<sampleCount { noisePointer[index] = generator.next() }

        var acousticInputs: [String: MLFeatureValue] = [
            "en": MLFeatureValue(multiArray: en),
            "asr": MLFeatureValue(multiArray: asr),
            "noise": MLFeatureValue(multiArray: noise),
        ]
        if let voiceArray { acousticInputs["voice"] = MLFeatureValue(multiArray: voiceArray) }
        try Task.checkCancellation()
        let acousticOut = try await acoustic.prediction(from: try MLDictionaryFeatureProvider(dictionary: acousticInputs))
        // A prediction may finish after its task was cancelled: never play it.
        try Task.checkCancellation()
        guard let audio = acousticOut.featureValue(for: "audio")?.multiArrayValue else {
            throw TTSError.predictionFailed("Paradee acoustic stage: missing 'audio'")
        }
        let length = audio.shape.last?.intValue ?? audio.count
        var samples = [Float](repeating: 0, count: length)
        let rank = audio.shape.count
        for index in 0..<length {
            var position = [Int](repeating: 0, count: rank)
            position[rank - 1] = index
            samples[index] = Self.float(audio, position)
        }
        return Output(samples: samples, frames: frames.map(Float.init), seconds: Date().timeIntervalSince(started))
    }

    /// [1,C,T] → [1,C,F], each column `t` repeated `frames[t]` times.
    private static func expand(_ source: MLMultiArray, frames: [Int], total: Int) throws -> MLMultiArray {
        let channels = source.shape[1].intValue
        let out = try MLMultiArray(shape: [1, NSNumber(value: channels), NSNumber(value: total)], dataType: .float32)
        let pointer = out.dataPointer.bindMemory(to: Float.self, capacity: channels * total)
        let outStride = out.strides.map(\.intValue)
        for channel in 0..<channels {
            var column = 0
            for (t, repeats) in frames.enumerated() {
                let value = float(source, [0, channel, t])
                for _ in 0..<repeats {
                    pointer[channel * outStride[1] + column * outStride[2]] = value
                    column += 1
                }
            }
        }
        return out
    }

    /// One element by position, through the array's own strides and type.
    private static func float(_ array: MLMultiArray, _ position: [Int]) -> Float {
        let strides = array.strides.map(\.intValue)
        var offset = 0
        for (axis, index) in position.enumerated() { offset += index * strides[axis] }
        switch array.dataType {
        case .float32:
            return array.dataPointer.bindMemory(to: Float.self, capacity: offset + 1)[offset]
        case .float16:
            return Float(array.dataPointer.bindMemory(to: Float16.self, capacity: offset + 1)[offset])
        case .double:
            return Float(array.dataPointer.bindMemory(to: Double.self, capacity: offset + 1)[offset])
        default:
            return array[offset].floatValue
        }
    }
}

/// N(0,1) from a SplitMix64 stream (Box–Muller): the same seed, the same noise.
struct SeededGaussian {
    private var state: UInt64
    private var spare: Float?

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    private mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private mutating func uniform() -> Double {
        // (0, 1]: never 0, so the log below is finite.
        (Double(nextUInt64() >> 11) + 1) / 9_007_199_254_740_992
    }

    mutating func next() -> Float {
        if let spare {
            self.spare = nil
            return spare
        }
        let radius = (-2 * log(uniform())).squareRoot()
        let angle = 2 * Double.pi * uniform()
        spare = Float(radius * sin(angle))
        return Float(radius * cos(angle))
    }
}
