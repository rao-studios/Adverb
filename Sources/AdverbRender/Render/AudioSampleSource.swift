//
//  AudioSampleSource.swift
//  AdverbRender
//
//  WHAT: The sound under an asset, as 48 kHz stereo Float32: silence (every asset ships with an
//        audio track, so music can be added in an app), a song from its in-point with a gain and
//        a fade-out at the end card, a narration's clips laid at their starts, or both, the song
//        ducked under the voice.
//  PIN:  The silent render and the beatmapped one are the same code path; only this changes.
//

@preconcurrency import AVFoundation
import Accelerate
import Foundation

/// One spoken clip and where it lands in the video.
public struct VoiceClip: Sendable, Equatable {
    public var url: URL
    /// Video time the clip starts at.
    public var startReal: Double
    public var gainDB: Double

    public init(url: URL, startReal: Double, gainDB: Double = 0) { self.url = url; self.startReal = startReal; self.gainDB = gainDB }
}

/// A narration: its clips, normalised together to a peak and then given a gain.
public struct VoiceLayer: Sendable, Equatable {
    public var clips: [VoiceClip]
    public var gainDB: Double
    public var peakDBFS: Double

    public init(clips: [VoiceClip], gainDB: Double = 0, peakDBFS: Double = -1) { self.clips = clips; self.gainDB = gainDB; self.peakDBFS = peakDBFS }
}

public struct AudioMixSpec: Sendable, Equatable {
    public var song: URL?
    public var inPoint: Double
    public var duration: Double
    public var fadeOut: Double
    public var gainDB: Double
    public var voice: VoiceLayer?
    /// Lower the song under the voice.
    public var duck: Bool

    public init(song: URL, inPoint: Double, duration: Double, fadeOut: Double = 1.2, gainDB: Double = -3) {
        self.song = song; self.inPoint = inPoint; self.duration = duration; self.fadeOut = fadeOut; self.gainDB = gainDB
        self.voice = nil; self.duck = true
    }

    /// A narration alone, over silence.
    public init(voice: VoiceLayer, duration: Double, duck: Bool = true) {
        self.song = nil; self.inPoint = 0; self.duration = duration; self.fadeOut = 0; self.gainDB = 0; self.voice = voice; self.duck = duck
    }

    public var isSilent: Bool { song == nil && (voice?.clips.isEmpty ?? true) }
}

public enum AudioSampleSource {
    public static let sampleRate: Double = 48_000
    public static let channels = 2

    /// Interleaved stereo samples for `duration` seconds: zeros, the song's segment, the
    /// narration, or the song ducked under the narration.
    public static func samples(duration: Double, mix: AudioMixSpec?) async throws -> [Float] {
        let frames = Int((duration * sampleRate).rounded())
        guard let mix, !mix.isSilent else { return [Float](repeating: 0, count: frames * channels) }
        var pcm = [Float](repeating: 0, count: frames * channels)
        if let song = mix.song { pcm = try await bed(song, mix: mix, frames: frames) }
        if let layer = mix.voice, !layer.clips.isEmpty {
            let voice = try await voiceSamples(layer, frames: frames)
            if mix.song != nil, mix.duck {
                let gains = duckGains(voice: voice, frames: frames)
                for f in 0..<frames { pcm[f * 2] *= gains[f]; pcm[f * 2 + 1] *= gains[f] }
            }
            vDSP_vadd(pcm, 1, voice, 1, &pcm, 1, vDSP_Length(pcm.count))
        }
        var lo: Float = -0.999, hi: Float = 0.999
        vDSP_vclip(pcm, 1, &lo, &hi, &pcm, 1, vDSP_Length(pcm.count))
        return pcm
    }

    /// The song from its in-point, at its gain, fading out over the last `fadeOut` seconds.
    static func bed(_ song: URL, mix: AudioMixSpec, frames: Int) async throws -> [Float] {
        let duration = Double(frames) / sampleRate
        var pcm = try await decode(song, from: mix.inPoint, duration: duration)
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

    /// Every clip decoded and laid at its start, the whole narration peak-normalised (lines keep
    /// their levels relative to each other), then the layer's gain.
    /// PIN: an mp3 clip starts with ~20–50 ms of encoder padding, and the TTS timings are relative
    /// to the clip's first sample, so captions are right to a frame or two, not to the sample.
    static func voiceSamples(_ layer: VoiceLayer, frames: Int) async throws -> [Float] {
        var placed: [(samples: [Float], startReal: Double)] = []
        for clip in layer.clips {
            var pcm = try await decodeWhole(clip.url)
            if clip.gainDB != 0 {
                var g = Float(pow(10, clip.gainDB / 20))
                vDSP_vsmul(pcm, 1, &g, &pcm, 1, vDSP_Length(pcm.count))
            }
            placed.append((pcm, clip.startReal))
        }
        var out = place(placed, frames: frames)
        var peak: Float = 0
        vDSP_maxmgv(out, 1, &peak, vDSP_Length(out.count))
        if peak > 1e-5 {
            let target = Float(pow(10, layer.peakDBFS / 20))
            // At most +12 dB: a near-silent take is not turned into noise.
            var scale = min(target / peak, 4) * Float(pow(10, layer.gainDB / 20))
            vDSP_vsmul(out, 1, &scale, &out, 1, vDSP_Length(out.count))
        }
        return out
    }

    /// Clips summed into one stereo buffer at their starts; what runs past the end is cut.
    public static func place(_ clips: [(samples: [Float], startReal: Double)], frames: Int) -> [Float] {
        var out = [Float](repeating: 0, count: frames * channels)
        for clip in clips {
            let startFrame = Int((max(0, clip.startReal) * sampleRate).rounded())
            guard startFrame < frames else { continue }
            let count = min(clip.samples.count / channels, frames - startFrame)
            guard count > 0 else { continue }
            out.withUnsafeMutableBufferPointer { dst in
                clip.samples.withUnsafeBufferPointer { src in
                    let d = dst.baseAddress! + startFrame * channels
                    vDSP_vadd(d, 1, src.baseAddress!, 1, d, 1, vDSP_Length(count * channels))
                }
            }
        }
        return out
    }

    /// Per-frame gain for the song under a voice: a peak follower on the voice decides when it
    /// speaks, and the song eases down `depthDB` over `attack` and back over `release`.
    public static func duckGains(voice: [Float], frames: Int, depthDB: Double = -10, attack: Double = 0.08, release: Double = 0.4,
                                 thresholdDB: Double = -40) -> [Float] {
        let sr = Float(sampleRate)
        let threshold = Float(pow(10, thresholdDB / 20))
        let depth = Float(pow(10, depthDB / 20))
        let envAttack = expf(-1 / (0.005 * sr)), envRelease = expf(-1 / (0.05 * sr))
        let up = expf(-1 / (Float(attack) * sr)), down = expf(-1 / (Float(release) * sr))
        var gains = [Float](repeating: 1, count: frames)
        var env: Float = 0, presence: Float = 0
        let n = min(frames, voice.count / channels)
        for f in 0..<frames {
            let x = f < n ? max(abs(voice[f * 2]), abs(voice[f * 2 + 1])) : 0
            env = x > env ? envAttack * env + (1 - envAttack) * x : envRelease * env + (1 - envRelease) * x
            let target: Float = env > threshold ? 1 : 0
            presence = target > presence ? up * presence + (1 - up) * target : down * presence + (1 - down) * target
            gains[f] = 1 - (1 - depth) * presence
        }
        return gains
    }

    /// A file's length in seconds, nil when AVFoundation cannot read it.
    public static func length(_ url: URL) async -> Double? {
        guard let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    /// A whole file, as 48 kHz stereo Float32.
    public static func decodeWhole(_ url: URL) async throws -> [Float] {
        let length = try await AVURLAsset(url: url).load(.duration).seconds
        return try await decode(url, from: 0, duration: max(0.01, length))
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
