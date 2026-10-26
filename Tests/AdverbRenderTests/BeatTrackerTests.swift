import Foundation
import Testing
@testable import AdverbCore
@testable import AdverbRender

/// Synthesised audio at 22.05 kHz with known beats.
enum Synth {
    static let sr = 22_050.0

    struct Noise {
        var state: UInt64 = 0x9E3779B97F4A7C15
        mutating func next() -> Float { state = state &* 6364136223846793005 &+ 1442695040888963407; return Float(Int64(bitPattern: state >> 11) % 2_000_000) / 1_000_000 - 1 }
    }

    static func silence(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * sr)) }

    static func add(_ x: inout [Float], at t: Double, _ burst: [Float]) {
        let start = Int(t * sr)
        for (i, v) in burst.enumerated() where start + i < x.count { x[start + i] += v }
    }

    static func click(gain: Float = 0.8) -> [Float] {
        (0..<Int(0.008 * sr)).map { i in gain * sinf(2 * .pi * 1000 * Float(i) / Float(sr)) * (1 - Float(i) / Float(0.008 * sr)) }
    }

    static func kick(gain: Float) -> [Float] {
        (0..<Int(0.08 * sr)).map { i in let t = Float(i) / Float(sr); return gain * sinf(2 * .pi * (60 + 60 * expf(-t * 30)) * t) * expf(-t * 25) }
    }

    static func snare(gain: Float) -> [Float] {
        var n = Noise()
        return (0..<Int(0.06 * sr)).map { i in gain * n.next() * expf(-Float(i) / Float(sr) * 40) }
    }

    static func hat(gain: Float) -> [Float] {
        var n = Noise(state: 7)
        return (0..<Int(0.02 * sr)).map { i in gain * n.next() * expf(-Float(i) / Float(sr) * 150) }
    }

    static func noiseFloor(_ x: inout [Float], gain: Float) {
        var n = Noise(state: 99)
        for i in 0..<x.count { x[i] += gain * n.next() }
    }

    static func clickTrack(bpm: Double, seconds: Double = 20, offset: Double = 0.3) -> ([Float], [Double]) {
        var x = silence(seconds)
        let beats = stride(from: offset, to: seconds - 0.1, by: 60 / bpm).map { $0 }
        for b in beats { add(&x, at: b, click()) }
        noiseFloor(&x, gain: 0.03)
        return (x, beats)
    }

    /// Four on the floor with the downbeat accented, snare on 2 and 4.
    static func kickPattern(bpm: Double, seconds: Double = 20, offset: Double = 0.5, swingHats: Bool = false) -> ([Float], [Double], [Double]) {
        var x = silence(seconds)
        let period = 60 / bpm
        let beats = stride(from: offset, to: seconds - 0.2, by: period).map { $0 }
        for (i, b) in beats.enumerated() {
            add(&x, at: b, kick(gain: i % 4 == 0 ? 1.0 : 0.45))
            if i % 4 == 1 || i % 4 == 3 { add(&x, at: b, snare(gain: 0.35)) }
            if swingHats {
                add(&x, at: b, hat(gain: 0.15))
                add(&x, at: b + period * 0.62, hat(gain: 0.12))
            }
        }
        noiseFloor(&x, gain: 0.01)
        return (x, beats, stride(from: 0, to: beats.count, by: 4).map { beats[$0] })
    }
}

@Suite struct BeatTrackerTests {
    func hitRate(_ found: [Double], _ truth: [Double], tolerance: Double = 0.05) -> Double {
        // Skip the first and last second, where the tracker has no context.
        let inner = truth.filter { $0 > 1 && $0 < (truth.last ?? 0) - 1 }
        guard !inner.isEmpty else { return 0 }
        let hits = inner.filter { t in found.contains { abs($0 - t) <= tolerance } }
        return Double(hits.count) / Double(inner.count)
    }

    @Test(arguments: [100.0, 128.0, 174.0])
    func clickTracks(bpm: Double) {
        let (x, truth) = Synth.clickTrack(bpm: bpm)
        let grid = BeatAnalysis.analyze(samples: x)
        let ok = abs(grid.bpm - bpm) <= 2 || abs(grid.bpm - bpm / 2) <= 2 || abs(grid.bpm - bpm * 2) <= 2
        #expect(ok, "bpm \(grid.bpm) for \(bpm)")
        #expect(!grid.nominal)
        if abs(grid.bpm - bpm) <= 2 { #expect(hitRate(grid.beats, truth) >= 0.95, "hit rate \(hitRate(grid.beats, truth))") }
    }

    @Test func kickPatternFindsTheDownbeat() {
        let (x, truth, downs) = Synth.kickPattern(bpm: 120)
        let grid = BeatAnalysis.analyze(samples: x)
        #expect(abs(grid.bpm - 120) <= 2, "bpm \(grid.bpm)")
        #expect(hitRate(grid.beats, truth) >= 0.9)
        #expect(hitRate(grid.downbeats, downs) >= 0.75, "downbeats \(grid.downbeats.prefix(4)) vs \(downs.prefix(4))")
    }

    @Test func swingKeepsTheTempo() {
        let (x, truth, _) = Synth.kickPattern(bpm: 96, swingHats: true)
        let grid = BeatAnalysis.analyze(samples: x)
        #expect(abs(grid.bpm - 96) <= 2, "bpm \(grid.bpm)")
        #expect(hitRate(grid.beats, truth) >= 0.9)
    }

    @Test func silenceAndNoiseAreLowConfidence() {
        let silent = BeatAnalysis.analyze(samples: Synth.silence(10))
        #expect(silent.confidence < 0.2)
        #expect(silent.nominal)
        var noise = Synth.silence(10)
        Synth.noiseFloor(&noise, gain: 0.5)
        let noisy = BeatAnalysis.analyze(samples: noise)
        #expect(noisy.confidence < 0.3, "confidence \(noisy.confidence)")
        #expect(noisy.nominal)
    }

    @Test func energyRiseIsFound() {
        var x = Synth.silence(3)
        let (music, _, _) = Synth.kickPattern(bpm: 120, seconds: 12, offset: 0.0)
        x += music
        let grid = BeatAnalysis.analyze(samples: x)
        let rise = grid.energy.firstIndex { $0 > 0.05 }.map { Double($0) * grid.energyHop } ?? -1
        #expect(abs(rise - 3.0) <= 0.1, "rise at \(rise)")
        #expect(grid.suggestedInPoint(for: 6) >= 2.9)
    }
}
