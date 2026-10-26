//
//  Spectrogram.swift
//  AdverbRender
//
//  WHAT: A short-time Fourier transform (Hann window 2048, hop 512 at 22.05 kHz: 43 frames a
//        second) folded straight into 64 log-mel bands, 30 Hz to 11 kHz. What the onset detector
//        and the downbeat estimator read.
//

import Accelerate
import Foundation

public struct Spectrogram: Sendable {
    public let bands: Int
    public let frames: Int
    /// frames × bands, row-major, log(1 + 1000·mel power).
    public let mel: [Float]
    public let fps: Double

    public func row(_ i: Int) -> ArraySlice<Float> { mel[(i * bands)..<((i + 1) * bands)] }

    public static func make(_ x: [Float], sampleRate: Double, n: Int = 2048, hop: Int = 512, bands: Int = 64,
                            fmin: Double = 30, fmax: Double = 11_000) -> Spectrogram {
        let half = n / 2
        let frames = x.count >= n ? 1 + (x.count - n) / hop : 0
        guard frames > 0, let setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(n), .FORWARD) else {
            return Spectrogram(bands: bands, frames: 0, mel: [], fps: sampleRate / Double(hop))
        }
        defer { vDSP_DFT_DestroySetup(setup) }
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
        let filters = melFilters(n: n, sampleRate: sampleRate, bands: bands, fmin: fmin, fmax: fmax)   // bands × half
        var mel = [Float](repeating: 0, count: frames * bands)
        var frame = [Float](repeating: 0, count: n)
        var evens = [Float](repeating: 0, count: half), odds = [Float](repeating: 0, count: half)
        var outR = [Float](repeating: 0, count: half), outI = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        var melRow = [Float](repeating: 0, count: bands)
        for f in 0..<frames {
            x.withUnsafeBufferPointer { xs in
                vDSP_vmul(xs.baseAddress! + f * hop, 1, window, 1, &frame, 1, vDSP_Length(n))
            }
            for k in 0..<half { evens[k] = frame[2 * k]; odds[k] = frame[2 * k + 1] }
            vDSP_DFT_Execute(setup, evens, odds, &outR, &outI)
            // zrop packs DC in outR[0] and Nyquist in outI[0]; the rest are bins 1…half−1.
            power[0] = outR[0] * outR[0]
            for k in 1..<half { power[k] = outR[k] * outR[k] + outI[k] * outI[k] }
            filters.withUnsafeBufferPointer { w in
                vDSP_mmul(w.baseAddress!, 1, power, 1, &melRow, 1, vDSP_Length(bands), 1, vDSP_Length(half))
            }
            for b in 0..<bands { mel[f * bands + b] = log1pf(1000 * melRow[b] / Float(n)) }
        }
        return Spectrogram(bands: bands, frames: frames, mel: mel, fps: sampleRate / Double(hop))
    }

    /// Triangular mel filters, bands × (n/2), slaney-style area normalisation.
    static func melFilters(n: Int, sampleRate: Double, bands: Int, fmin: Double, fmax: Double) -> [Float] {
        func hzToMel(_ f: Double) -> Double { 2595 * log10(1 + f / 700) }
        func melToHz(_ m: Double) -> Double { 700 * (pow(10, m / 2595) - 1) }
        let half = n / 2
        let lo = hzToMel(fmin), hi = hzToMel(min(fmax, sampleRate / 2))
        let points = (0...(bands + 1)).map { melToHz(lo + (hi - lo) * Double($0) / Double(bands + 1)) }
        var w = [Float](repeating: 0, count: bands * half)
        for b in 0..<bands {
            let l = points[b], c = points[b + 1], r = points[b + 2]
            let norm = 2 / (r - l)
            for k in 0..<half {
                let f = Double(k) * sampleRate / Double(n)
                let v = f <= l || f >= r ? 0 : (f <= c ? (f - l) / (c - l) : (r - f) / (r - c))
                w[b * half + k] = Float(v * norm)
            }
        }
        return w
    }
}
