//
//  AudioSampleSource.swift
//  AdverbRender
//
//  WHAT: The sound under an asset, as 48 kHz stereo Float32: silence (every asset ships with an
//        audio track, so music can be added in an app), or a song from its in-point with a gain
//        and a fade-out at the end card.
//  PIN:  The silent render and the beatmapped one are the same code path; only this changes.
//

@preconcurrency import AVFoundation
import Accelerate
import Foundation

public struct AudioMixSpec: Sendable, Equatable {
    public var song: URL
    public var inPoint: Double
    public var duration: Double
    public var fadeOut: Double
    public var gainDB: Double

    public init(song: URL, inPoint: Double, duration: Double, fadeOut: Double = 1.2, gainDB: Double = -3) {
        self.song = song; self.inPoint = inPoint; self.duration = duration; self.fadeOut = fadeOut; self.gainDB = gainDB
    }
}

public enum AudioSampleSource {
    public static let sampleRate: Double = 48_000
    public static let channels = 2

    /// Interleaved stereo samples for `duration` seconds: zeros, or the song's segment.
    public static func samples(duration: Double, mix: AudioMixSpec?) async throws -> [Float] {
        let frames = Int((duration * sampleRate).rounded())
        guard let mix else { return [Float](repeating: 0, count: frames * channels) }
        var pcm = try await decode(mix.song, from: mix.inPoint, duration: duration)
        if pcm.count < frames * channels { pcm += [Float](repeating: 0, count: frames * channels - pcm.count) }
        if pcm.count > frames * channels { pcm.removeLast(pcm.count - frames * channels) }
        var gain = Float(pow(10, mix.gainDB / 20))
        vDSP_vsmul(pcm, 1, &gain, &pcm, 1, vDSP_Length(pcm.count))
        // The fade: from full to silence over the last `fadeOut` seconds.
        let fadeFrames = min(frames, Int(mix.fadeOut * sampleRate))
        if fadeFrames > 0 {
            let start = frames - fadeFrames
            for f in 0..<fadeFrames {
                let x = Float(f) / Float(fadeFrames)
                let g = 1 - x * x * (3 - 2 * x)   // smoothstep down
                pcm[(start + f) * 2] *= g
                pcm[(start + f) * 2 + 1] *= g
            }
        }
        return pcm
    }

    /// The song from `start` for `duration` seconds, resampled to 48 kHz stereo Float32 by
    /// AVAssetReader (any container AVFoundation reads: mp3, m4a, aif, wav).
    public static func decode(_ url: URL, from start: Double, duration: Double) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw RenderError.writer("no audio track in \(url.lastPathComponent)")
        }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: max(0, start), preferredTimescale: 48_000),
                                       duration: CMTime(seconds: duration, preferredTimescale: 48_000))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw RenderError.writer(reader.error?.localizedDescription ?? "reader") }
        var out: [Float] = []
        out.reserveCapacity(Int(duration * sampleRate) * channels)
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            chunk.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            out += chunk
        }
        if reader.status == .failed { throw RenderError.writer(reader.error?.localizedDescription ?? "reader failed") }
        return out
    }
}
