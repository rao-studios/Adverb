//
//  AudioRemux.swift
//  AdverbRender
//
//  WHAT: A finished video with new sound: its video track copied untouched (the compressed
//        samples, no re-encode, no re-render) under a new AAC track. How a voice-over in another
//        language, another voice, or a voice added to a built asset reaches its MP4s in seconds.
//  PIN:  Written to a temporary file and copied over the destination, which may be the source.
//        Faststart, as every Adverb MP4 is; the inspector checks the result like a render.
//

@preconcurrency import AVFoundation
import AdverbCore
import Foundation

public enum AudioRemux {
    /// `source`'s frames under the sound `mix` makes for the video's own length.
    public static func replaceAudio(in source: URL, mix: AudioMixSpec?, to destination: URL,
                                    expecting: (duration: Double, orientation: Orientation)? = nil) async throws -> RenderReport {
        let duration = try await AVURLAsset(url: source).load(.duration).seconds
        let samples = try await AudioSampleSource.samples(duration: duration, mix: mix)
        return try await replaceAudio(in: source, with: samples, to: destination, expecting: expecting)
    }

    /// `source`'s frames under `samples` (48 kHz interleaved stereo Float32).
    public static func replaceAudio(in source: URL, with samples: [Float], to destination: URL,
                                    expecting: (duration: Double, orientation: Orientation)? = nil) async throws -> RenderReport {
        let started = Date()
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw RenderError.writer("no video track in \(source.lastPathComponent)") }
        let (formats, transform) = try await track.load(.formatDescriptions, .preferredTransform)
        let duration = try await asset.load(.duration)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("adverb-remux-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temp) }
        let writer = try AVAssetWriter(outputURL: temp, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formats.first)
        video.expectsMediaDataInRealTime = false
        video.transform = transform
        let audio = try AudioTrackFeeder(samples: samples)
        guard writer.canAdd(video), writer.canAdd(audio.input) else { throw RenderError.writer("remux inputs") }
        writer.add(video)
        writer.add(audio.input)
        guard reader.startReading() else { throw RenderError.writer(reader.error?.localizedDescription ?? "reader") }
        guard writer.startWriting() else { throw RenderError.writer(writer.error?.localizedDescription ?? "start") }
        writer.startSession(atSourceTime: .zero)

        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            try await audio.feed(until: (pts.isNumeric ? pts.seconds : 0) + 1.0, writer: writer)
            // As in MP4Writer: while the video input waits, it is waiting for audio.
            while !video.isReadyForMoreMediaData {
                if writer.status == .failed { throw RenderError.writer(writer.error?.localizedDescription ?? "failed") }
                if !audio.isDone, audio.input.isReadyForMoreMediaData, audio.hasMore {
                    try audio.appendChunk(writer: writer)
                } else {
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
            }
            guard video.append(sample) else { throw RenderError.writer(writer.error?.localizedDescription ?? "append video sample") }
        }
        if reader.status == .failed { throw RenderError.writer(reader.error?.localizedDescription ?? "reader failed") }
        try await audio.feed(until: .infinity, writer: writer)
        audio.finishIfDone()
        video.markAsFinished()
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        if writer.status != .completed { throw RenderError.writer(writer.error?.localizedDescription ?? "finish") }
        try AtomicFile.replace(destination, with: temp)
        return try await RenderInspector.inspect(destination, expecting: expecting, renderSeconds: Date().timeIntervalSince(started))
    }
}
