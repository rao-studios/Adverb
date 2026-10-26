//
//  RenderInspector.swift
//  AdverbRender
//
//  WHAT: An MP4 checked against what it should be (rao-motion-assets §4 step 7, without ffprobe):
//        |duration − DUR| ≤ 1 frame, frames = DUR × 30, the orientation's size, an audio track,
//        faststart. What does not match becomes a warning on the report.
//

@preconcurrency import AVFoundation
import AdverbCore
import Foundation

public enum RenderInspector {
    public static func inspect(_ url: URL, expecting: (duration: Double, orientation: Orientation)? = nil,
                               renderSeconds: Double? = nil) async throws -> RenderReport {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return RenderReport(duration: duration, frameCount: 0, fps: 0, width: 0, height: 0, bitrate: 0, hasAudio: false,
                                audio: nil, fastStart: false, renderSeconds: renderSeconds, warnings: ["no video track"])
        }
        let (size, transform, rate, fps) = try await track.load(.naturalSize, .preferredTransform, .estimatedDataRate, .nominalFrameRate)
        let shown = size.applying(transform)
        let width = Int(abs(shown.width).rounded()), height = Int(abs(shown.height).rounded())
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioLine: String?
        if let a = audioTracks.first, let format = try await a.load(.formatDescriptions).first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
            let codec = asbd.mFormatID == kAudioFormatMPEG4AAC ? "AAC" : "audio"
            audioLine = "\(codec) \(Int(asbd.mSampleRate / 1000)) kHz \(asbd.mChannelsPerFrame == 2 ? "stereo" : "\(asbd.mChannelsPerFrame) ch")"
        }
        let frames = try countFrames(asset: asset, track: track)
        let fast = Mp4Atoms.isFastStart(Mp4Atoms.topLevel(url: url))
        var warnings: [String] = []
        if let expecting {
            let fpsWanted = 30.0
            if abs(duration - expecting.duration) > 1 / fpsWanted + 1e-3 { warnings.append(String(format: "length %.3f s, wanted %.0f s", duration, expecting.duration)) }
            let wantFrames = Int((expecting.duration * fpsWanted).rounded())
            if frames != wantFrames { warnings.append("\(frames) frames, wanted \(wantFrames)") }
            if width != expecting.orientation.width || height != expecting.orientation.height {
                warnings.append("\(width)×\(height), wanted \(expecting.orientation.width)×\(expecting.orientation.height)")
            }
            if audioTracks.isEmpty { warnings.append("no audio track") }
            if !fast { warnings.append("not faststart") }
        }
        return RenderReport(duration: duration, frameCount: frames, fps: Double(fps), width: width, height: height,
                            bitrate: Double(rate), hasAudio: !audioTracks.isEmpty, audio: audioLine, fastStart: fast,
                            renderSeconds: renderSeconds, warnings: warnings)
    }

    /// Compressed samples, counted without decoding.
    static func countFrames(asset: AVAsset, track: AVAssetTrack) throws -> Int {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { return 0 }
        var count = 0
        while let sample = output.copyNextSampleBuffer() { count += CMSampleBufferGetNumSamples(sample) }
        return count
    }
}
