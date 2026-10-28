//
//  AudioTrackFeeder.swift
//  AdverbRender
//
//  WHAT: An AAC 48 kHz stereo track fed to an AVAssetWriter from interleaved Float32 samples, in
//        1024-frame chunks: the encoder's audio half, shared by MP4Writer (frames in) and
//        AudioRemux (a finished video's samples in).
//

@preconcurrency import AVFoundation
import Foundation

final class AudioTrackFeeder: @unchecked Sendable {
    let input: AVAssetWriterInput
    private let format: CMAudioFormatDescription
    private let samples: [Float]
    private var cursor = 0   // in frames (stereo pairs)
    private(set) var isDone = false

    init(samples: [Float]) throws {
        self.samples = samples
        var asbd = AudioStreamBasicDescription(mSampleRate: AudioSampleSource.sampleRate, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
                                               mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        guard let description else { throw RenderError.writer("audio format") }
        format = description
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: AudioSampleSource.sampleRate,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000,
        ])
        input.expectsMediaDataInRealTime = false
    }

    var totalFrames: Int { samples.count / 2 }
    var hasMore: Bool { cursor < totalFrames }

    /// Appends audio up to `seconds` (all of it at .infinity). Mid-stream, a closed input means
    /// the writer wants video first: it returns and lets the caller give it.
    func feed(until seconds: Double, writer: AVAssetWriter) async throws {
        guard !isDone else { return }
        let limit = seconds.isInfinite ? totalFrames : min(totalFrames, Int(seconds * AudioSampleSource.sampleRate))
        while cursor < limit {
            var waited = 0
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw RenderError.writer(writer.error?.localizedDescription ?? "failed") }
                if !seconds.isInfinite, waited > 5 { return }
                waited += 1
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            try appendChunk(limit: limit, writer: writer)
        }
    }

    func appendChunk(limit: Int? = nil, writer: AVAssetWriter) throws {
        let end = limit ?? totalFrames
        let count = min(1024, end - cursor)
        guard count > 0 else { return }
        let buffer = try makeBuffer(from: cursor, count: count)
        guard input.append(buffer) else { throw RenderError.writer(writer.error?.localizedDescription ?? "append audio") }
        cursor += count
        finishIfDone()
    }

    /// PIN: the writer interleaves the tracks, and an audio input that has run out of samples but
    /// is not marked finished makes it hold the video back, waiting for audio that never comes
    /// (reproduced: a frame every 80 ms stalls at the audio's end). Finished the moment the last
    /// sample is in.
    func finishIfDone() {
        guard !isDone, cursor >= totalFrames else { return }
        input.markAsFinished()
        isDone = true
    }

    private func makeBuffer(from start: Int, count: Int) throws -> CMSampleBuffer {
        let bytes = count * 8
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                                        customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                                                        flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard status == noErr, let block else { throw RenderError.writer("audio block \(status)") }
        status = samples.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!.advanced(by: start * 8), blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        }
        guard status == noErr else { throw RenderError.writer("audio copy \(status)") }
        var sample: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(AudioSampleSource.sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw RenderError.writer("audio sample \(status)") }
        return sample
    }
}
