//
//  KokoroSeamDSP.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: How Kokoro pieces meet: edges trimmed to the voice and faded, one
//        gain per voice instead of every chunk normalized to full scale.
//  IN:   KokoroEngine+Render (options.seams)
//  OUT:  pieces ready to be joined with KokoroPause silences
//  PIN:  A trim never reaches past the silence the model itself put at an
//        edge (`pred_dur` of BOS, or of EOS and a closing mark): a soft
//        onset or a breathy tail under the threshold stays.
//  PIN:  ChunkEdgeDSP is the hosted voice's; it is called here, never edited.
//  PIN:  The gain and the limiter are every voice's: SewnTTSEngine brings its
//        chunks to `replyLoudnessDb` through them too.
//

import Accelerate
import Foundation

enum KokoroSeamDSP {

    /// Samples per `pred_dur` frame (24 kHz, hop 600: 25 ms).
    static let samplesPerFrame = 600

    /// What the reference sentences are brought to (voicedLoudness, raw).
    /// Replies rendered through the finished chain then land at −19 dBFS,
    /// the legacy path's own median (every chunk peak-normalized): she is as
    /// loud as before, only evenly. The reference sentences read ~2.2 dB
    /// hotter than running speech after the filters (measured 2026-09-28).
    static let targetLoudnessDb: Float = -16.8
    /// Where her replies land (voicedLoudness of running speech): what a
    /// voice measured on its own replies, not on the reference sentences, is
    /// brought to — the hosted one pins its gain from its first chunk.
    static let replyLoudnessDb: Float = -19
    /// What the limiter lets through.
    static let ceiling: Float = 0.95

    /// Edge silence that may go: what the model said at BOS, and at EOS plus
    /// a final mark. The vocoder rings on past EOS (a sentence's tail measured
    /// 300 ms against 175 ms of EOS and mark), so the tail gets 12 frames more.
    static func trimBounds(predDur: [Float], endsOnMark: Bool) -> (lead: Int, tail: Int) {
        guard predDur.count >= 2 else { return (0, 0) }
        let frames = { (value: Float) in Int(value.rounded()) }
        let lead = frames(predDur[0]) + 2
        var tail = frames(predDur[predDur.count - 1]) + 12
        if endsOnMark, predDur.count >= 3 { tail += frames(predDur[predDur.count - 2]) }
        return (lead * samplesPerFrame, tail * samplesPerFrame)
    }

    /// Edges below `thresholdDb` removed, up to the bounds, keeping `guardMs`
    /// of what was under the threshold; then short fades.
    static func trimmed(
        _ samples: [Float], sampleRate: Double, leadMax: Int, tailMax: Int,
        thresholdDb: Float = ChunkEdgeDSP.defaultThresholdDb,
        guardMs: Double = ChunkEdgeDSP.defaultGuardMs
    ) -> (samples: [Float], lead: Int, tail: Int) {
        guard !samples.isEmpty, sampleRate > 0 else { return (samples, 0, 0) }
        let threshold = powf(10, thresholdDb / 20)
        let guardSamples = Int(sampleRate * guardMs / 1_000)
        var first = samples.count
        var last = -1
        samples.withUnsafeBufferPointer { buffer in
            if let index = buffer.firstIndex(where: { abs($0) >= threshold }) { first = index }
            if let index = buffer.lastIndex(where: { abs($0) >= threshold }) { last = index }
        }
        guard last >= first else {
            // All silence: a guard's worth, never nothing.
            let keep = max(guardSamples, 1)
            return (Array(samples.prefix(keep)), 0, max(0, samples.count - keep))
        }
        let lead = min(max(0, first - guardSamples), leadMax)
        let tail = min(max(0, samples.count - 1 - last - guardSamples), tailMax)
        var kept = Array(samples[lead..<(samples.count - tail)])
        ChunkEdgeDSP.edgeFades(&kept, sampleRate: sampleRate)
        return (kept, lead, tail)
    }

    /// `pieces` joined with each piece's pause after it (the last's is dropped).
    static func joined(_ pieces: [(samples: [Float], pauseAfter: KokoroPause)], sampleRate: Double) -> [Float] {
        var out: [Float] = []
        for (index, piece) in pieces.enumerated() {
            out.append(contentsOf: piece.samples)
            if index < pieces.count - 1 {
                out.append(contentsOf: repeatElement(0, count: Int(sampleRate * piece.pauseAfter.seconds)))
            }
        }
        return out
    }

    /// The finished chunk: the existing rumble and sibilance filters, the
    /// voice's gain, the limiter, and faded edges.
    static func finish(_ samples: inout [Float], sampleRate: Double, gain: Float) {
        guard !samples.isEmpty else { return }
        KokoroDSP.removeRumble(&samples, sampleRate: Float(sampleRate), cutoffHz: 80)
        KokoroDSP.deEss(&samples, sampleRate: Float(sampleRate), cutoffHz: 6_000, reductionDb: -3.0)
        ChunkEdgeDSP.applyGain(&samples, gain: gain)
        limit(&samples, sampleRate: sampleRate)
        ChunkEdgeDSP.edgeFades(&samples, sampleRate: sampleRate)
    }

    /// The gain that brings `loudnessDb` (voicedLoudness) to `target`.
    static func gain(loudnessDb: Float, target: Float = targetLoudnessDb) -> Float {
        guard loudnessDb.isFinite, loudnessDb > -80 else { return 1 }
        return min(max(powf(10, (target - loudnessDb) / 20), 0.5), 6)
    }

    /// Median RMS of the voiced 50 ms windows, in dBFS; -inf for silence.
    static func voicedLoudness(_ samples: [Float], sampleRate: Double) -> Float {
        let window = max(1, Int(sampleRate * 0.05))
        var levels: [Float] = []
        var start = 0
        while start + window <= samples.count {
            var rms: Float = 0
            samples.withUnsafeBufferPointer { buffer in
                vDSP_rmsqv(buffer.baseAddress! + start, 1, &rms, vDSP_Length(window))
            }
            if rms > 0.01 { levels.append(rms) }  // −40 dBFS: voiced
            start += window
        }
        guard !levels.isEmpty else { return -.infinity }
        levels.sort()
        return 20 * log10f(levels[levels.count / 2])
    }

    /// A look-ahead peak limiter. The gain ramps down over `lookaheadMs` to
    /// meet a peak exactly and recovers over `releaseMs`: loudness stays one
    /// level, and nothing clips or crackles as a hard clip would.
    static func limit(
        _ samples: inout [Float], sampleRate: Double,
        ceiling: Float = ceiling, lookaheadMs: Double = 5, releaseMs: Double = 80
    ) {
        let count = samples.count
        let look = max(1, Int(sampleRate * lookaheadMs / 1_000))
        var gains = [Float](repeating: 1, count: count)
        var peaked = false
        for index in 0..<count {
            let level = abs(samples[index])
            guard level > ceiling else { continue }
            peaked = true
            let need = ceiling / level
            // Ramp from 1 at `look` samples before, down to `need` at the peak.
            for back in 0...min(look, index) {
                let ramp = need + (1 - need) * Float(back) / Float(look)
                if ramp < gains[index - back] { gains[index - back] = ramp }
            }
        }
        guard peaked else { return }
        let release = expf(-1 / Float(sampleRate * releaseMs / 1_000))
        var envelope: Float = 1
        for index in 0..<count {
            let target = gains[index]
            envelope = target < envelope ? target : target + (envelope - target) * release
            samples[index] *= envelope
        }
    }
}
