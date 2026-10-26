//
//  BeatAnalysis.swift
//  AdverbRender
//
//  WHAT: The beat tracker, in five steps over a log-mel spectrogram:
//        1. onset strength (SuperFlux: positive spectral change against a max-filtered frame two
//           back, with a moving-mean floor), and the same restricted to the low bands (the kick);
//        2. tempo from the onset envelope's autocorrelation over 60–200 BPM, weighted toward
//           120 BPM on a log scale, with an octave check;
//        3. beats by Ellis (2007) dynamic programming: each beat's score is its onset plus the best
//           previous beat's score, penalised by how far the gap is from one period;
//        4. downbeats: the phase of four that most often lands on strong onsets and the kick;
//        5. an energy envelope (RMS of 20 ms windows every 10 ms).
//  PIN:  Constant tempo. Octave errors (half or double time) are the commonest miss, which is why
//        the person gets ×2 / ÷2 and a downbeat nudge. Sparse or ambient music reports low
//        confidence, and below 0.3 the grid is nominal: the detected (or 120) BPM laid from the
//        first energy rise, and marked so.
//

import Accelerate
import AdverbCore
import Foundation

public enum BeatAnalysis {
    public static let sampleRate = 22_050.0

    public static func analyze(samples x: [Float], sampleRate: Double = sampleRate) -> BeatGrid {
        let duration = Double(x.count) / sampleRate
        let energy = energyEnvelope(x, sampleRate: sampleRate)
        let spec = Spectrogram.make(x, sampleRate: sampleRate)
        guard spec.frames > 64 else {
            return nominal(bpm: 120, duration: duration, energy: energy, confidence: 0)
        }
        let onset = onsetEnvelope(spec, from: 0, to: spec.bands)
        let low = onsetEnvelope(spec, from: 0, to: 8)
        let (bpm, confidence) = tempo(onset: onset, fps: spec.fps)
        if confidence < 0.3 { return nominal(bpm: bpm, duration: duration, energy: energy, confidence: confidence) }
        let frames = track(onset: onset, fps: spec.fps, bpm: bpm)
        guard frames.count >= 4 else { return nominal(bpm: bpm, duration: duration, energy: energy, confidence: confidence) }
        let hop = 1 / spec.fps
        // A frame's time is its window's centre.
        let beats = frames.map { (Double($0) + 0.5) * hop + 1024 / sampleRate - 0.5 * hop }
        let phase = downbeatPhase(beatFrames: frames, onset: onset, low: low, lowLevel: lowLevel(spec, bands: 6))
        let downbeats = stride(from: phase, to: beats.count, by: 4).map { beats[$0] }
        return BeatGrid(bpm: (bpm * 10).rounded() / 10, confidence: confidence, beats: beats.map(round3), downbeats: downbeats.map(round3),
                        energy: energy, energyHop: 0.010, duration: duration)
    }

    // MARK: 1. Onsets

    static func onsetEnvelope(_ spec: Spectrogram, from lo: Int, to hi: Int) -> [Float] {
        var out = [Float](repeating: 0, count: spec.frames)
        let lag = 2
        for f in lag..<spec.frames {
            let cur = spec.row(f), prev = spec.row(f - lag)
            var sum: Float = 0
            for b in lo..<hi {
                let p = max(prev[prev.startIndex + max(lo, b - 1)], prev[prev.startIndex + b], prev[prev.startIndex + min(hi - 1, b + 1)])
                let d = cur[cur.startIndex + b] - p
                if d > 0 { sum += d }
            }
            out[f] = sum
        }
        // Subtract a half-second moving mean, keep what rises above it.
        let w = max(1, Int(0.5 * spec.fps))
        var mean = [Float](repeating: 0, count: out.count)
        var acc: Float = 0
        for i in 0..<out.count {
            acc += out[i]
            if i >= w { acc -= out[i - w] }
            mean[i] = acc / Float(min(i + 1, w))
        }
        for i in 0..<out.count { out[i] = max(0, out[i] - mean[i]) }
        let p95 = percentile(out, 0.95)
        if p95 > 0 { for i in 0..<out.count { out[i] = min(out[i] / p95, 4) } }
        return out
    }

    /// Mean log-mel level of the lowest `bands`, per frame, scaled to 0…1.
    static func lowLevel(_ spec: Spectrogram, bands: Int) -> [Float] {
        var out = (0..<spec.frames).map { f -> Float in
            let row = spec.row(f)
            return row.prefix(bands).reduce(0, +) / Float(bands)
        }
        let lo = out.min() ?? 0, hi = out.max() ?? 1
        if hi > lo { for i in 0..<out.count { out[i] = (out[i] - lo) / (hi - lo) } }
        return out
    }

    // MARK: 2. Tempo

    static func tempo(onset: [Float], fps: Double, range: ClosedRange<Double> = 60...200, prior: Double = 120) -> (Double, Double) {
        let minLag = Int(floor(60 * fps / range.upperBound)), maxLag = Int(ceil(60 * fps / range.lowerBound))
        guard onset.count > maxLag * 4 else { return (prior, 0) }
        var acf = [Float](repeating: 0, count: maxLag + 2)
        let n = onset.count
        onset.withUnsafeBufferPointer { o in
            for lag in 0...(maxLag + 1) {
                var s: Float = 0
                vDSP_dotpr(o.baseAddress!, 1, o.baseAddress! + lag, 1, &s, vDSP_Length(n - lag))
                acf[lag] = s / Float(n - lag)
            }
        }
        guard acf[0] > 0 else { return (prior, 0) }
        let priorLag = 60 * fps / prior
        func weight(_ lag: Double) -> Double { exp(-0.5 * pow(log2(lag / priorLag) / 1.0, 2)) }
        var best = minLag, bestScore = -Double.infinity
        for lag in minLag...maxLag {
            let score = Double(acf[lag]) * weight(Double(lag))
            if score > bestScore { bestScore = score; best = lag }
        }
        // Parabolic refinement of the raw peak.
        var lag = Double(best)
        if best > minLag, best < maxLag {
            let a = Double(acf[best - 1]), b = Double(acf[best]), c = Double(acf[best + 1])
            let d = a - 2 * b + c
            if d != 0 { lag += 0.5 * (a - c) / d }
        }
        var bpm = 60 * fps / lag
        // Octave check: prefer the double or half that is nearly as periodic and lands in 80–160.
        for factor in [2.0, 0.5] {
            let other = bpm * factor
            let otherLag = Int((60 * fps / other).rounded())
            if (80...160).contains(other), !(80...160).contains(bpm), otherLag >= 1, otherLag <= maxLag + 1,
               Double(acf[otherLag]) >= 0.8 * Double(acf[best]) {
                bpm = other
            }
        }
        let inRange = Array(acf[minLag...maxLag]).map(Double.init)
        let mean = inRange.reduce(0, +) / Double(inRange.count)
        let peak = Double(acf[best])
        let confidence = max(0, min(1, (peak - mean) / max(1e-9, Double(acf[0]) - mean) * 2.2))
        return (bpm, confidence)
    }

    // MARK: 3. Beats

    static func track(onset: [Float], fps: Double, bpm: Double, tightness: Double = 100) -> [Int] {
        let period = 60 * fps / bpm
        let n = onset.count
        let std = Double(standardDeviation(onset))
        let o = onset.map { Double($0) / max(std, 1e-9) }
        var score = [Double](repeating: 0, count: n)
        var back = [Int](repeating: -1, count: n)
        let lo = Int((period / 2).rounded()), hi = Int((period * 2).rounded())
        for t in 0..<n {
            var bestPrev = -1, bestValue = 0.0
            if t - lo >= 0 {
                for prev in max(0, t - hi)...(t - lo) {
                    let gap = Double(t - prev)
                    let v = score[prev] - tightness * pow(log(gap / period), 2)
                    if bestPrev < 0 || v > bestValue { bestValue = v; bestPrev = prev }
                }
            }
            score[t] = o[t] + (bestPrev >= 0 ? max(0, bestValue) : 0)
            back[t] = bestPrev >= 0 && bestValue > 0 ? bestPrev : -1
        }
        // The last beat: the best score in the final period.
        let tail = max(0, n - Int(period.rounded()))
        var end = tail
        for t in tail..<n where score[t] > score[end] { end = t }
        var beats: [Int] = []
        var t = end
        while t >= 0 { beats.append(t); t = back[t] }
        beats.reverse()
        // Refine each to the local onset peak within one frame.
        return beats.map { b in
            var best = b
            for c in max(0, b - 1)...min(n - 1, b + 1) where onset[c] > onset[best] { best = c }
            return best
        }
    }

    // MARK: 4. Downbeats

    /// The bar's first beat is where the kick is heaviest: low-band level and low-band change
    /// carry most of the weight; the broadband onset (which a snare on 2 and 4 also lights) little.
    static func downbeatPhase(beatFrames: [Int], onset: [Float], low: [Float], lowLevel: [Float] = [], meter: Int = 4) -> Int {
        var best = 0, bestScore = -Float.infinity
        let level = lowLevel.isEmpty ? low : lowLevel
        for phase in 0..<meter {
            var s: Float = 0, count: Float = 0
            for i in stride(from: phase, to: beatFrames.count, by: meter) {
                let f = beatFrames[i]
                // The strongest of the beat's own frame and the next two: a kick's low end peaks a beat later.
                let peakLow = (f..<min(level.count, f + 3)).map { level[$0] }.max() ?? 0
                let peakFlux = (f..<min(low.count, f + 3)).map { low[$0] }.max() ?? 0
                s += 0.15 * onset[f] + 0.35 * peakFlux + 0.5 * peakLow; count += 1
            }
            let mean = count > 0 ? s / count : 0
            if mean > bestScore { bestScore = mean; best = phase }
        }
        return best
    }

    // MARK: 5. Energy

    static func energyEnvelope(_ x: [Float], sampleRate: Double, hop: Double = 0.010, window: Double = 0.020) -> [Float] {
        let w = Int(window * sampleRate)
        let count = Int(Double(x.count) / sampleRate / hop)
        guard w > 0, count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        x.withUnsafeBufferPointer { xs in
            for i in 0..<count {
                let start = Int(Double(i) * hop * sampleRate)
                let len = min(w, x.count - start)
                guard len > 0 else { break }
                var r: Float = 0
                vDSP_rmsqv(xs.baseAddress! + start, 1, &r, vDSP_Length(len))
                out[i] = r
            }
        }
        let p99 = percentile(out, 0.99)
        if p99 > 0 { for i in 0..<out.count { out[i] = min(1, out[i] / p99) } }
        return out
    }

    // MARK: Nominal

    /// A grid at `bpm` from the first energy rise: what sparse music gets, marked nominal.
    static func nominal(bpm: Double, duration: Double, energy: [Float], confidence: Double) -> BeatGrid {
        let base = BeatGrid(bpm: bpm, confidence: confidence, beats: [], downbeats: [], energy: energy, energyHop: 0.010, duration: duration)
        let start = base.suggestedInPoint(for: 0)
        let period = 60 / max(bpm, 1)
        let beats = stride(from: start, to: duration, by: period).map(round3)
        let downbeats = stride(from: 0, to: beats.count, by: 4).map { beats[$0] }
        return BeatGrid(bpm: (bpm * 10).rounded() / 10, confidence: confidence, beats: beats, downbeats: downbeats, energy: energy,
                        energyHop: 0.010, duration: duration, nominal: true)
    }

    // MARK: Helpers

    static func percentile(_ x: [Float], _ p: Double) -> Float {
        guard !x.isEmpty else { return 0 }
        let sorted = x.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }

    static func standardDeviation(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        var mean: Float = 0, sd: Float = 0
        vDSP_normalize(x, 1, nil, 1, &mean, &sd, vDSP_Length(x.count))
        return sd
    }

    static func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
}

/// Analysis of song files, cached by path and modification date.
public actor BeatAnalyzer {
    public static let shared = BeatAnalyzer()
    private var cache: [String: BeatGrid] = [:]
    private let folder: URL

    public init(cacheFolder: URL = AdverbHome.caches.appendingPathComponent("beats", isDirectory: true)) { folder = cacheFolder }

    public func analyze(_ url: URL) async throws -> BeatGrid {
        let key = cacheKey(url)
        if let hit = cache[key] { return hit }
        let file = folder.appendingPathComponent("\(key).json")
        if let stored = try? JSONCoding.read(BeatGrid.self, from: file) { cache[key] = stored; return stored }
        let (samples, _) = try await AudioDecoder.mono(url, sampleRate: BeatAnalysis.sampleRate)
        let grid = await Task.detached(priority: .userInitiated) { BeatAnalysis.analyze(samples: samples) }.value
        cache[key] = grid
        try? JSONCoding.write(grid, to: file)
        return grid
    }

    /// A grid re-analysed on the segment the asset uses (local tempo is steadier than global), in
    /// video time.
    public func analyzeWindow(_ url: URL, inPoint: Double, duration: Double) async throws -> BeatGrid {
        let pad = 5.0
        let start = max(0, inPoint - pad)
        let (samples, _) = try await AudioDecoder.mono(url, sampleRate: BeatAnalysis.sampleRate, range: start...(inPoint + duration + pad))
        let local = await Task.detached(priority: .userInitiated) { BeatAnalysis.analyze(samples: samples) }.value
        return local.window(inPoint: inPoint - start, duration: duration)
    }

    public nonisolated func cacheKey(_ url: URL) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let raw = "\(url.standardizedFileURL.path)|\(Int(modified))|v1"
        var h: UInt64 = 1469598103934665603
        for b in raw.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 16)
    }
}
