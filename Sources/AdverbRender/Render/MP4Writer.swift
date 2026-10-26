//
//  MP4Writer.swift
//  AdverbRender
//
//  WHAT: The one encoder every renderer feeds: frames in as CGImages, an H.264 High MP4 out at
//        30 fps with an AAC 48 kHz stereo track, faststart.
//  PIN:  Frames arrive lossless (a snapshot, never a JPEG in between, as the skill's pipe used) and
//        are encoded at a fixed average bitrate well above what crf 17 gave the flat platinum pages
//        (~1.7 Mbps), so motion, grain and fine serif edges keep their detail. Pixel buffers are
//        drawn in sRGB and tagged ITU-R 709, the convention VideoToolbox converts with.
//        The file is written to a temporary folder and copied to its destination once finished:
//        no moov rewrites on the slow external drive.
//

@preconcurrency import AVFoundation
import CoreVideo
import Foundation

public struct EncoderSettings: Sendable, Equatable {
    public var fps: Int32 = 30
    public var bitrate: Int = 12_000_000
    public var keyframeInterval: Int = 60
    public init(fps: Int32 = 30, bitrate: Int = 12_000_000, keyframeInterval: Int = 60) {
        self.fps = fps; self.bitrate = bitrate; self.keyframeInterval = keyframeInterval
    }
}

public final class MP4Writer: @unchecked Sendable {
    public let url: URL
    public let width: Int
    public let height: Int
    private let settings: EncoderSettings
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audio: AVAssetWriterInput
    private let audioFormat: CMAudioFormatDescription
    private var audioSamples: [Float]
    private var audioCursor = 0   // in frames (stereo pairs)
    private var audioFinished = false
    private var frameCount = 0

    public init(url: URL, width: Int, height: Int, settings: EncoderSettings = .init(), audio samples: [Float]) throws {
        self.url = url; self.width = width; self.height = height; self.settings = settings; self.audioSamples = samples
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let color: [String: Any] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: color,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                AVVideoMaxKeyFrameIntervalKey: settings.keyframeInterval,
                AVVideoAllowFrameReorderingKey: true,
                AVVideoExpectedSourceFrameRateKey: Int(settings.fps),
            ] as [String: Any],
        ])
        video.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ])
        var asbd = AudioStreamBasicDescription(mSampleRate: AudioSampleSource.sampleRate, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
                                               mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard let format else { throw RenderError.writer("audio format") }
        audioFormat = format
        audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: AudioSampleSource.sampleRate,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000,
        ])
        audio.expectsMediaDataInRealTime = false
        guard writer.canAdd(video), writer.canAdd(audio) else { throw RenderError.writer("inputs") }
        writer.add(video)
        writer.add(audio)
        guard writer.startWriting() else { throw RenderError.writer(writer.error?.localizedDescription ?? "start") }
        writer.startSession(atSourceTime: .zero)
    }

    public var frames: Int { frameCount }

    /// Appends the next frame (W×H, any CG format) and the audio up to its time.
    public func append(_ image: CGImage) async throws {
        let time = CMTime(value: CMTimeValue(frameCount), timescale: settings.fps)
        try await feedAudio(until: Double(frameCount + 1) / Double(settings.fps) + 1.0)
        // The writer interleaves the two tracks: while video waits, it is waiting for audio, so
        // keep the audio coming until the video input opens.
        while !video.isReadyForMoreMediaData {
            if writer.status == .failed { throw RenderError.writer(writer.error?.localizedDescription ?? "failed") }
            if !audioFinished, audio.isReadyForMoreMediaData, audioCursor < audioSamples.count / 2 {
                try appendAudioChunk()
            } else {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        guard let pool = adaptor.pixelBufferPool else { throw RenderError.writer("no pixel buffer pool") }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw RenderError.writer("pixel buffer") }
        try Self.draw(image, into: buffer, width: width, height: height)
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw RenderError.writer(writer.error?.localizedDescription ?? "append frame \(frameCount)")
        }
        frameCount += 1
    }

    public func finish() async throws {
        try await feedAudio(until: .infinity)
        finishAudioIfDone()
        video.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frameCount), timescale: settings.fps))
        await writer.finishWriting()
        if writer.status != .completed { throw RenderError.writer(writer.error?.localizedDescription ?? "finish") }
    }

    public func cancel() {
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Audio

    private func feedAudio(until seconds: Double) async throws {
        guard !audioFinished else { return }
        let totalFrames = audioSamples.count / 2
        let limit = seconds.isInfinite ? totalFrames : min(totalFrames, Int(seconds * AudioSampleSource.sampleRate))
        while audioCursor < limit {
            var waited = 0
            while !audio.isReadyForMoreMediaData {
                if writer.status == .failed { throw RenderError.writer(writer.error?.localizedDescription ?? "failed") }
                // Mid-render, a closed audio input means the writer wants video first: go and give it.
                if !seconds.isInfinite, waited > 5 { return }
                waited += 1
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            try appendAudioChunk(limit: limit)
        }
    }

    private func appendAudioChunk(limit: Int? = nil) throws {
        let end = limit ?? audioSamples.count / 2
        let count = min(1024, end - audioCursor)
        guard count > 0 else { return }
        let buffer = try makeAudioBuffer(from: audioCursor, count: count)
        guard audio.append(buffer) else { throw RenderError.writer(writer.error?.localizedDescription ?? "append audio") }
        audioCursor += count
        finishAudioIfDone()
    }

    /// PIN: the writer interleaves the tracks, and an audio input that has run out of samples but
    /// is not marked finished makes it hold the video back, waiting for audio that never comes
    /// (reproduced: a frame every 80 ms stalls at the audio's end). Finished the moment the last
    /// sample is in.
    private func finishAudioIfDone() {
        guard !audioFinished, audioCursor >= audioSamples.count / 2 else { return }
        audio.markAsFinished()
        audioFinished = true
    }

    private func makeAudioBuffer(from start: Int, count: Int) throws -> CMSampleBuffer {
        let bytes = count * 8
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                                        customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                                                        flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard status == noErr, let block else { throw RenderError.writer("audio block \(status)") }
        status = audioSamples.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!.advanced(by: start * 8), blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        }
        guard status == noErr else { throw RenderError.writer("audio copy \(status)") }
        var sample: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: audioFormat, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(AudioSampleSource.sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw RenderError.writer("audio sample \(status)") }
        return sample
    }

    // MARK: - Pixels

    static func draw(_ image: CGImage, into buffer: CVPixelBuffer, width: Int, height: Int) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: ImageScaler.sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw RenderError.writer("pixel context") }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(red: 0.937, green: 0.933, blue: 0.918, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    }
}
