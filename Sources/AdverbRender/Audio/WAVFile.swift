//
//  WAVFile.swift
//  AdverbRender
//
//  WHAT: Mono Float32 samples to a 16-bit PCM WAV file: a voice-over line as the on-device voice
//        speaks it, read back by AVFoundation (AudioSampleSource) like any other clip.
//

import AdverbCore
import Foundation

public enum WAVFile {
    public static func write(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        let rate = UInt32(sampleRate.rounded())
        let dataBytes = UInt32(samples.count * 2)
        var data = Data(capacity: 44 + Int(dataBytes))
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        var pcm = [Int16](repeating: 0, count: samples.count)
        for (i, s) in samples.enumerated() { pcm[i] = Int16(max(-1, min(1, s.isFinite ? s : 0)) * 32_767) }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        try AtomicFile.write(data, to: url)
    }
}
