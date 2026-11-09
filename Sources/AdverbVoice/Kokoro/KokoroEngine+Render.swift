//
//  KokoroEngine+Render.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: One chunk of text → one finished waveform: phonemized with its
//        punctuation, cut where the window needs it, each piece spoken and
//        its seams made, then one gain for the voice.
//  IN:   synthesizeChunk / synthesizeWaveform (KokoroEngine+PublicAPI)
//  OUT:  SynthesizedChunk; KokoroSynthesisDiagnostics to whoever listens
//  PIN:  `.legacy` runs the shipped path unchanged (`legacyWaveform`).
//  PIN:  One chunk at a time (`withGate`): a chunk's rate, report and pieces
//        are its own, even with the speaker's prefetch asking for two.
//  PIN:  ADVERB: each word's span in the finished waveform (`wordSpans`), from the
//        model's own per-token frame counts, the lead each piece's seam trimmed and
//        the pauses the join put between pieces; and the student's `speed`. The
//        rest is Ambient's render as it was lifted.
//

import Foundation
@preconcurrency import CoreML

/// What one chunk's synthesis did, for the probe's `--diag` and `bench`.
package struct KokoroSynthesisDiagnostics: Sendable {
    package struct Call: Sendable {
        package var tokens: Int
        package var variant: String
        /// Sum of `pred_dur`: the audio the model meant to make, in 25 ms frames.
        package var frames: Int
        package var seconds: Double
        package var clipped: Bool
        package var phonemes: String
        package var pauseAfter: KokoroPause
        /// Each mark's `pred_dur`, in frames, in order.
        package var markFrames: [(mark: String, frames: Int)]
        package var trimmedMs: (lead: Double, tail: Double)
        package var rawPeak: Float
    }
    package var text: String
    package var options: KokoroOptions
    package var calls: [Call] = []
    package var audioSeconds: Double = 0
    package var computeSeconds: Double = 0
}

/// One model call's result.
struct KokoroModelOutput {
    var samples: [Float]
    /// One entry per input id (BOS and EOS included).
    var predDur: [Float]
    var variant: TTSVariant
    var seconds: Double
    /// The model meant more audio than its window holds.
    var clipped: Bool
}

extension KokoroEngine {

    /// af_heart's reference sentences, raw (KokoroSeamDSP.voicedLoudness, as
    /// warmUp measures them; 2026-09-28), until warmUp measures the loaded voice.
    static let typicalLoudnessDb: Float = -22.2

    // MARK: - The gate

    /// Runs `body` alone: calls queue in arrival order.
    func withGate<T>(_ body: () async throws -> T) async throws -> T {
        if gateBusy {
            await withCheckedContinuation { gateWaiters.append($0) }
        } else {
            gateBusy = true
        }
        defer {
            if gateWaiters.isEmpty {
                gateBusy = false
            } else {
                gateWaiters.removeFirst().resume()
            }
        }
        try Task.checkCancellation()
        return try await body()
    }

    // MARK: - One chunk

    func render(_ text: String, options: KokoroOptions) async throws -> SynthesizedChunk {
        guard !loadedModels.isEmpty || paradee != nil else { throw TTSError.modelsNotLoaded }
        guard hasVoice else { throw TTSError.noVoiceLoaded }
        if options == .legacy, paradee == nil {
            let samples = try await legacyWaveform(text)
            return SynthesizedChunk(samples: samples, sampleRate: sampleRate, pronunciation: lastPronunciationReport)
        }

        var diagnostics = KokoroSynthesisDiagnostics(text: text, options: options)
        let started = Date()
        let pieces: [(ids: [Int32], pauseAfter: KokoroPause)]
        let report: PronunciationReport
        let largest = maxTokensPerCall
        var words: [(text: String, ids: [Int32])] = []

        if options.punctuation {
            let phonemes = await phonemizer.phonemizeUnits(text, options: options)
            words = phonemes.units.compactMap { unit in
                guard case .word(let w) = unit.kind, !unit.ids.isEmpty else { return nil }
                return (w, unit.ids)
            }
            if options.segments {
                pieces = KokoroSegmenter.plan(phonemes).map {
                    ([0] + phonemes.ids($0.range, closeWith: $0.closeWith) + [0], $0.pauseAfter)
                }
            } else {
                let content = Array(phonemes.ids(0..<phonemes.units.count, closeWith: ".").prefix(largest - 2))
                pieces = [([0] + content + [0], .none)]
            }
            var traced = phonemes.report
            traced.totalTokens = pieces.reduce(0) { $0 + $1.ids.count }
            traced.phonemes = pieces.map { phonemes.render(Array($0.ids.dropFirst().dropLast())) }
                .joined(separator: " | ")
            report = traced
        } else {
            let (ids, traced) = await phonemizer.phonemize(text, maxTokens: largest, options: options)
            pieces = [(ids.count > largest ? Array(ids.prefix(largest - 1)) + [0] : ids, .none)]
            report = traced
        }
        try Task.checkCancellation()
        publish(report)

        var spoken: [(samples: [Float], pauseAfter: KokoroPause)] = []
        var timing: [(ids: [Int32], predDur: [Float], lead: Int)] = []
        var rate = sampleRate
        for piece in pieces where piece.ids.count > 2 {
            let said = try await speakPiece(
                piece.ids, pauseAfter: piece.pauseAfter, options: options, diagnostics: &diagnostics)
            for part in said {
                rate = part.output.variant.sampleRate
                var samples = part.output.samples
                var lead = 0
                if options.seams {
                    let bounds = KokoroSeamDSP.trimBounds(
                        predDur: part.output.predDur, endsOnMark: isPausingMark(part.ids.lastContentID))
                    let trim = KokoroSeamDSP.trimmed(
                        samples, sampleRate: rate, leadMax: bounds.lead, tailMax: bounds.tail)
                    samples = trim.samples
                    lead = trim.lead
                    if let index = part.call {
                        diagnostics.calls[index].trimmedMs = (
                            lead: Double(trim.lead) / rate * 1000, tail: Double(trim.tail) / rate * 1000)
                    }
                }
                spoken.append((samples, part.pause))
                timing.append((part.ids, part.output.predDur, lead))
            }
        }

        var waveform: [Float]
        if options.seams {
            waveform = KokoroSeamDSP.joined(spoken, sampleRate: rate)
            let typical = paradee != nil ? ParadeeBackend.typicalLoudnessDb : Self.typicalLoudnessDb
            KokoroSeamDSP.finish(&waveform, sampleRate: rate, gain: voiceGain ?? KokoroSeamDSP.gain(loudnessDb: typical))
        } else {
            waveform = spoken.flatMap(\.samples)
            KokoroDSP.applyPostProcessing(&waveform, sampleRate: Float(rate))
        }
        sampleRate = rate
        diagnostics.audioSeconds = Double(waveform.count) / rate
        diagnostics.computeSeconds = Date().timeIntervalSince(started)
        onDiagnostics?(diagnostics)
        let spans = options.seams ? Self.wordSpans(words: words, parts: timing, spoken: spoken, sampleRate: rate) : []
        return SynthesizedChunk(samples: waveform, sampleRate: rate, pronunciation: report, wordSpans: spans)
    }

    /// Each word's span in the joined waveform: the parts' ids walked against the words' own ids in
    /// order, each id's frames from the model (25 ms each at 24 kHz), less the lead its seam trimmed,
    /// plus every part and pause before it. Empty when the walk does not account for every word.
    static func wordSpans(words: [(text: String, ids: [Int32])], parts: [(ids: [Int32], predDur: [Float], lead: Int)],
                          spoken: [(samples: [Float], pauseAfter: KokoroPause)], sampleRate: Double) -> [KokoroWordSpan] {
        guard !words.isEmpty, parts.count == spoken.count, parts.allSatisfy({ $0.predDur.count >= $0.ids.count }) else { return [] }
        let perFrame = sampleRate * 0.025
        var spans: [KokoroWordSpan] = []
        var next = 0
        var offset = 0.0
        for (p, part) in parts.enumerated() {
            var frames: [Double] = [0]
            for d in part.predDur.prefix(part.ids.count) { frames.append(frames.last! + Double(max(0, d.rounded()))) }
            var i = 1
            while i < part.ids.count - 1 {
                if next < words.count {
                    let w = words[next].ids
                    if i + w.count <= part.ids.count, Array(part.ids[i..<(i + w.count)]) == w {
                        let start = max(0, frames[i] * perFrame - Double(part.lead))
                        let end = max(start, frames[i + w.count] * perFrame - Double(part.lead))
                        spans.append(KokoroWordSpan(text: words[next].text, start: (offset + start) / sampleRate, end: (offset + end) / sampleRate))
                        next += 1
                        i += w.count
                        continue
                    }
                }
                i += 1
            }
            offset += Double(spoken[p].samples.count)
            if p < parts.count - 1 { offset += Double(Int(sampleRate * spoken[p].pauseAfter.seconds)) }
        }
        return next == words.count ? spans : []
    }

    /// A piece through the model: the smallest window that holds its audio,
    /// and when even the largest clips, the piece halved and each half spoken.
    private func speakPiece(
        _ piece: [Int32], pauseAfter: KokoroPause, options: KokoroOptions,
        diagnostics: inout KokoroSynthesisDiagnostics, depth: Int = 0
    ) async throws -> [(output: KokoroModelOutput, ids: [Int32], pause: KokoroPause, call: Int?)] {
        if let backend = paradee {
            return try await speakStudentPiece(
                piece, backend: backend, pauseAfter: pauseAfter, options: options,
                diagnostics: &diagnostics, depth: depth)
        }
        guard let voice = currentVoice else { throw TTSError.noVoiceLoaded }
        var ids = piece
        if let largest = loadedModels.last?.variant.maxTokens, ids.count > largest {
            // One unbroken run past every window (a word the segmenter could
            // not cut): halve it; past the last depth, cut it to fit.
            if options.segments, depth < 6 {
                return try await halve(ids, pauseAfter: pauseAfter, options: options,
                                       diagnostics: &diagnostics, depth: depth)
            }
            ids = Array(ids.prefix(largest - 1)) + [0]
        }
        guard let embedding = voice.embedding(for: ids.count - 2, style: options.styleVector) else {
            throw TTSError.noVoiceLoaded
        }
        var candidates = loadedModels.filter { $0.variant.maxTokens >= ids.count }
        if let first = selectModel(for: ids.count),
           let index = candidates.firstIndex(where: { $0.variant.name == first.variant.name }) {
            candidates = Array(candidates[index...])
        }
        var output: KokoroModelOutput?
        for model in candidates {
            let attempt = try await runModel(ids: ids, embedding: embedding, model: model)
            diagnostics.calls.append(call(ids, attempt, pauseAfter))
            output = attempt
            if !attempt.clipped { break }
        }
        guard let output else { throw TTSError.modelsNotLoaded }
        guard output.clipped, options.segments, depth < 3, ids.count > 8 else {
            return [(output, ids, pauseAfter, diagnostics.calls.count - 1)]
        }
        // Still too long for the largest window's audio: halve and speak both.
        return try await halve(ids, pauseAfter: pauseAfter, options: options,
                               diagnostics: &diagnostics, depth: depth)
    }

    /// A piece through the student: any length its window holds, nothing to
    /// clip; one longer than the window is halved as Kokoro's would be.
    private func speakStudentPiece(
        _ piece: [Int32], backend: ParadeeBackend, pauseAfter: KokoroPause, options: KokoroOptions,
        diagnostics: inout KokoroSynthesisDiagnostics, depth: Int
    ) async throws -> [(output: KokoroModelOutput, ids: [Int32], pause: KokoroPause, call: Int?)] {
        guard let voice = paradeeVoice else { throw TTSError.noVoiceLoaded }
        var ids = piece
        if ids.count > backend.maxTokens {
            if options.segments, depth < 6 {
                return try await halve(ids, pauseAfter: pauseAfter, options: options,
                                       diagnostics: &diagnostics, depth: depth)
            }
            ids = Array(ids.prefix(backend.maxTokens - 1)) + [0]
        }
        let result = try await backend.run(ids: ids, voice: voice.index, speed: speed, seed: nextNoiseSeed())
        let window = TTSVariant(
            name: "paradee", sampleRate: backend.sampleRate, maxTokens: backend.maxTokens,
            maxSamples: backend.maxFrames * backend.samplesPerFrame)
        let output = KokoroModelOutput(
            samples: result.samples, predDur: result.frames, variant: window,
            seconds: result.seconds, clipped: false)
        diagnostics.calls.append(call(ids, output, pauseAfter))
        return [(output, ids, pauseAfter, diagnostics.calls.count - 1)]
    }

    /// `ids` in two at the space nearest the middle (or the middle itself),
    /// each half spoken; the cut gets a word's pause.
    private func halve(
        _ ids: [Int32], pauseAfter: KokoroPause, options: KokoroOptions,
        diagnostics: inout KokoroSynthesisDiagnostics, depth: Int
    ) async throws -> [(output: KokoroModelOutput, ids: [Int32], pause: KokoroPause, call: Int?)] {
        let content = Array(ids.dropFirst().dropLast())
        let middle = content.count / 2
        let space = phonemizer.spaceTokenID()
        let spaceCut = content[middle...].firstIndex(where: { $0 == space })
            ?? content[..<middle].lastIndex(where: { $0 == space })
        // A space is dropped at the cut; a cut with no space keeps every id.
        let leftEnd = spaceCut ?? middle
        let rightStart = spaceCut.map { $0 + 1 } ?? middle
        let left = try await speakPiece(
            [0] + Array(content[..<leftEnd]) + [0], pauseAfter: .word, options: options,
            diagnostics: &diagnostics, depth: depth + 1)
        let right = try await speakPiece(
            [0] + Array(content[rightStart...]) + [0], pauseAfter: pauseAfter, options: options,
            diagnostics: &diagnostics, depth: depth + 1)
        return left + right
    }

    private func call(_ ids: [Int32], _ output: KokoroModelOutput, _ pause: KokoroPause) -> KokoroSynthesisDiagnostics.Call {
        var marks: [(String, Int)] = []
        for (index, id) in ids.enumerated() where index < output.predDur.count {
            if let mark = phonemizer.markSymbol(for: id) {
                marks.append((mark, Int(output.predDur[index].rounded())))
            }
        }
        return .init(
            tokens: ids.count - 2, variant: output.variant.name,
            frames: Int(output.predDur.reduce(0, +).rounded()), seconds: output.seconds,
            clipped: output.clipped, phonemes: phonemizer.render(ids), pauseAfter: pause,
            markFrames: marks, trimmedMs: (0, 0), rawPeak: ChunkEdgeDSP.peak(output.samples))
    }

    private func isPausingMark(_ id: Int32?) -> Bool {
        guard let id, let mark = phonemizer.markSymbol(for: id) else { return false }
        return KokoroLexer.pausing.contains(mark)
    }

    func publish(_ report: PronunciationReport) {
        lastPronunciationReport = report
        for continuation in pronunciationContinuations.values {
            continuation.yield(report)
        }
    }

    // MARK: - The model

    /// One call. Inputs, prediction and extraction exactly as shipped; also
    /// reads `pred_dur` and whether the audio ran past the window.
    func runModel(ids: [Int32], embedding: [Float], model selected: LoadedModel) async throws -> KokoroModelOutput {
        let variant = selected.variant
        let maxTokens = variant.maxTokens
        let actualCount = ids.count
        let embDim = embedding.count

        let inputIDs = try MLMultiArray(shape: [1, NSNumber(value: maxTokens)], dataType: .int32)
        let inputPtr = inputIDs.dataPointer.bindMemory(to: Int32.self, capacity: maxTokens)
        inputPtr.initialize(repeating: 0, count: maxTokens)
        ids.withUnsafeBufferPointer { buf in
            inputPtr.update(from: buf.baseAddress!, count: buf.count)
        }

        let mask    = try MLMultiArray(shape: [1, NSNumber(value: maxTokens)], dataType: .int32)
        let maskPtr = mask.dataPointer.bindMemory(to: Int32.self, capacity: maxTokens)
        maskPtr.initialize(repeating: 0, count: maxTokens)
        for i in 0..<min(actualCount, maxTokens) { maskPtr[i] = 1 }

        let refS   = try MLMultiArray(shape: [1, NSNumber(value: embDim)], dataType: .float32)
        let refPtr = refS.dataPointer.bindMemory(to: Float.self, capacity: embDim)
        embedding.withUnsafeBufferPointer { buf in
            refPtr.update(from: buf.baseAddress!, count: buf.count)
        }

        // random_phases MUST be zeroed — random values cause garbled output
        let phases    = try MLMultiArray(shape: [1, 9], dataType: .float32)
        let phasesPtr = phases.dataPointer.bindMemory(to: Float.self, capacity: 9)
        phasesPtr.initialize(repeating: 0, count: 9)

        try Task.checkCancellation()
        let started = Date()
        let result = try await selected.model.prediction(from: try MLDictionaryFeatureProvider(dictionary: [
            "input_ids":      MLFeatureValue(multiArray: inputIDs),
            "ref_s":          MLFeatureValue(multiArray: refS),
            "random_phases":  MLFeatureValue(multiArray: phases),
            "attention_mask": MLFeatureValue(multiArray: mask),
        ]))
        let seconds = Date().timeIntervalSince(started)
        // Core ML prediction may finish normally after its parent task was
        // cancelled. Never turn that obsolete output into playable PCM.
        try Task.checkCancellation()

        guard let audioArray = result.featureValue(for: "audio")?.multiArrayValue else {
            throw TTSError.predictionFailed("Missing 'audio' output")
        }

        var effectiveCount = audioArray.count
        var reported = 0
        if let lenArray = result.featureValue(for: "audio_length_samples")?.multiArrayValue,
           lenArray.count > 0 {
            let n = lenArray[0].intValue
            reported = n
            if n > 0 && n <= audioArray.count { effectiveCount = n }
        }
        effectiveCount = min(max(effectiveCount, 1), variant.maxSamples)

        var waveform = [Float](repeating: 0, count: effectiveCount)
        switch audioArray.dataType {
        case .float32:
            let ptr = audioArray.dataPointer.bindMemory(to: Float.self, capacity: audioArray.count)
            waveform.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.update(from: ptr, count: effectiveCount)
            }
        case .float16:
            let ptr = audioArray.dataPointer.bindMemory(to: UInt16.self, capacity: audioArray.count)
            for i in 0..<effectiveCount { waveform[i] = Float(Float16(bitPattern: ptr[i])) }
        default:
            for i in 0..<effectiveCount { waveform[i] = audioArray[i].floatValue }
        }

        var predDur: [Float] = []
        if let durations = result.featureValue(for: "pred_dur")?.multiArrayValue {
            let count = min(actualCount, durations.count)
            predDur.reserveCapacity(count)
            for i in 0..<count { predDur.append(durations[i].floatValue) }
        }

        return KokoroModelOutput(
            samples: waveform, predDur: predDur, variant: variant, seconds: seconds,
            clipped: reported > variant.maxSamples)
    }

    // MARK: - As shipped

    /// The voice before KokoroOptions: final-mark-only phonemes truncated to
    /// the window, the mean style vector, every chunk normalized to full scale.
    func legacyWaveform(_ text: String) async throws -> [Float] {
        guard let voice = currentVoice else { throw TTSError.noVoiceLoaded }

        let probeMaxTokens = loadedModels.last!.variant.maxTokens
        let (probeIDs, pronunciationReport) = await phonemizer.phonemize(text, maxTokens: probeMaxTokens, options: .legacy)
        try Task.checkCancellation()
        publish(pronunciationReport)
        let probeCount = probeIDs.count

        guard let selected = selectModel(for: probeCount) else { throw TTSError.modelsNotLoaded }
        let variant   = selected.variant
        let maxTokens = variant.maxTokens
        sampleRate = variant.sampleRate

        let ids: [Int32] = probeIDs.count > maxTokens
            ? Array(probeIDs.prefix(maxTokens - 1)) + [0]
            : probeIDs
        print("🎯 Selected model '\(variant.name)' for \(ids.count) tokens (probe=\(probeCount))")

        guard let embedding = voice.embedding(for: ids.count) else { throw TTSError.noVoiceLoaded }
        var waveform = try await runModel(ids: ids, embedding: embedding, model: selected).samples
        KokoroDSP.applyPostProcessing(&waveform, sampleRate: Float(sampleRate))
        return waveform
    }
}

private extension Array where Element == Int32 {
    /// The last id before EOS.
    var lastContentID: Int32? { count >= 2 ? self[count - 2] : nil }
}
