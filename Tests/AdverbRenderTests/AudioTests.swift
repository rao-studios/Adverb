import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import AdverbCore
@testable import AdverbRender

@Suite(.serialized) struct AudioTests {
    static func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("adverb-audio-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A stereo sine, interleaved.
    static func tone(seconds: Double, hz: Double = 1000, amplitude: Float = 0.5) -> [Float] {
        let n = Int(seconds * AudioSampleSource.sampleRate)
        var out = [Float](repeating: 0, count: n * 2)
        for i in 0..<n {
            let v = amplitude * Float(sin(2 * .pi * hz * Double(i) / AudioSampleSource.sampleRate))
            out[i * 2] = v; out[i * 2 + 1] = v
        }
        return out
    }

    static func rms(_ pcm: [Float], from: Double, to: Double) -> Float {
        let a = Int(from * AudioSampleSource.sampleRate) * 2, b = min(pcm.count, Int(to * AudioSampleSource.sampleRate) * 2)
        guard b > a else { return 0 }
        return sqrt(pcm[a..<b].reduce(0) { $0 + $1 * $1 } / Float(b - a))
    }

    /// A tiny silent MP4 the way the renderer makes one.
    static func silentVideo(frames: Int, to url: URL) async throws {
        let w = 64, h = 64
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        let writer = try MP4Writer(url: url, width: w, height: h, audio: [Float](repeating: 0, count: Int(Double(frames) / 30 * AudioSampleSource.sampleRate) * 2))
        for i in 0..<frames {
            ctx.setFillColor(CGColor(red: Double(i) / Double(frames), green: 0.4, blue: 0.6, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            try await writer.append(ctx.makeImage()!)
        }
        try await writer.finish()
    }

    static func writeWAV(_ pcm: [Float], to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: AudioSampleSource.sampleRate, channels: 2)!
        let frames = AVAudioFrameCount(pcm.count / 2)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = pcm[i * 2]; buffer.floatChannelData![1][i] = pcm[i * 2 + 1] }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    @Test func writerStillFinishesWithAudio() async throws {
        let url = Self.folder().appendingPathComponent("w.mp4")
        try await Self.silentVideo(frames: 10, to: url)
        let report = try await RenderInspector.inspect(url)
        #expect(report.frameCount == 10)
        #expect(report.hasAudio)
        #expect(report.fastStart)
    }

    @Test func remuxKeepsEveryFrameAndReplacesTheSound() async throws {
        let dir = Self.folder()
        let source = dir.appendingPathComponent("silent.mp4"), out = dir.appendingPathComponent("toned.mp4")
        try await Self.silentVideo(frames: 30, to: source)
        let before = try await AudioSampleSource.decodeWhole(source)
        #expect(Self.rms(before, from: 0.1, to: 0.9) < 0.001)
        let report = try await AudioRemux.replaceAudio(in: source, with: Self.tone(seconds: 1), to: out)
        #expect(report.frameCount == 30)
        #expect(abs(report.duration - 1) <= 1.0 / 30 + 1e-3)
        #expect(report.hasAudio && report.fastStart)
        #expect(report.audio == "AAC 48 kHz stereo")
        let after = try await AudioSampleSource.decodeWhole(out)
        #expect(Self.rms(after, from: 0.2, to: 0.8) > 0.2)
        // In place, over its own source.
        let again = try await AudioRemux.replaceAudio(in: out, with: [Float](repeating: 0, count: 96_000), to: out)
        #expect(again.frameCount == 30)
    }

    @Test func clipsArePlacedAtTheirStart() {
        let clip = Self.tone(seconds: 0.5)
        let pcm = AudioSampleSource.place([(clip, 2.0), (clip, 2.8)], frames: Int(3 * AudioSampleSource.sampleRate))
        #expect(pcm.count == Int(3 * AudioSampleSource.sampleRate) * 2)
        #expect(Self.rms(pcm, from: 1.5, to: 1.95) == 0)
        #expect(Self.rms(pcm, from: 2.05, to: 2.45) > 0.3)
        // The second clip is cut at the end.
        #expect(Self.rms(pcm, from: 2.85, to: 3.0) > 0.3)
    }

    @Test func theSongDucksUnderTheVoice() {
        let frames = Int(6 * AudioSampleSource.sampleRate)
        let voice = AudioSampleSource.place([(Self.tone(seconds: 1), 2.0)], frames: frames)
        let gains = AudioSampleSource.duckGains(voice: voice, frames: frames)
        func g(_ t: Double) -> Float { gains[Int(t * AudioSampleSource.sampleRate)] }
        #expect(g(1.0) > 0.999)
        #expect(g(2.15) < 0.5)
        #expect(abs(g(2.8) - 0.316) < 0.02)
        #expect(g(4.5) > 0.9)
    }

    @Test func aVoiceLayerReachesItsPeak() async throws {
        let dir = Self.folder()
        let wav = dir.appendingPathComponent("line.wav")
        try Self.writeWAV(Self.tone(seconds: 0.5, amplitude: 0.3), to: wav)
        let mix = AudioMixSpec(voice: VoiceLayer(clips: [VoiceClip(url: wav, startReal: 1.0)]), duration: 3)
        let pcm = try await AudioSampleSource.samples(duration: 3, mix: mix)
        #expect(Self.rms(pcm, from: 0.2, to: 0.9) == 0)
        #expect(Self.rms(pcm, from: 1.1, to: 1.4) > 0.5)
        var peak: Float = 0
        for v in pcm { peak = max(peak, abs(v)) }
        #expect(abs(peak - Float(pow(10, -1.0 / 20))) < 0.01)
        #expect(try await AudioSampleSource.samples(duration: 1, mix: AudioMixSpec(voice: VoiceLayer(clips: []), duration: 1)).allSatisfy { $0 == 0 })
        // A near-silent take is raised at most +12 dB, not to the peak.
        let quiet = dir.appendingPathComponent("quiet.wav")
        try Self.writeWAV(Self.tone(seconds: 0.5, amplitude: 0.05), to: quiet)
        let raised = try await AudioSampleSource.samples(duration: 1, mix: AudioMixSpec(voice: VoiceLayer(clips: [VoiceClip(url: quiet, startReal: 0)]), duration: 1))
        #expect((raised.map(abs).max() ?? 0) < 0.21)
    }
}
