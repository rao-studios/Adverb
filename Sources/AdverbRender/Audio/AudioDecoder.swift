//
//  AudioDecoder.swift
//  AdverbRender
//
//  WHAT: Any song AVFoundation reads (mp3, m4a, aif, wav) as mono Float32 at one sample rate,
//        resampled and downmixed by AVAssetReader itself (Frigate's audio reader, without MLX).
//

@preconcurrency import AVFoundation
import Foundation

public enum AudioDecoder {
    public static func mono(_ url: URL, sampleRate: Double = 22_050, range: ClosedRange<Double>? = nil) async throws -> (samples: [Float], duration: Double) {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw RenderError.writer("no audio in \(url.lastPathComponent)")
        }
        let reader = try AVAssetReader(asset: asset)
        if let range {
            let start = max(0, range.lowerBound), end = min(duration, range.upperBound)
            reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 44_100),
                                           duration: CMTime(seconds: max(0, end - start), preferredTimescale: 44_100))
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw RenderError.writer(reader.error?.localizedDescription ?? "audio reader") }
        var samples: [Float] = []
        samples.reserveCapacity(Int(duration * sampleRate))
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            let start = samples.count
            samples.append(contentsOf: repeatElement(0, count: count))
            samples.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!.advanced(by: start * 4))
            }
        }
        if reader.status == .failed { throw RenderError.writer(reader.error?.localizedDescription ?? "audio reader failed") }
        return (samples, duration)
    }
}
