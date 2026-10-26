//
//  FrameGrabber.swift
//  AdverbRender
//
//  WHAT: Exact frames out of an MP4 (zero tolerance), for contact sheets, overviews, the day
//        cell's thumbnail and quality checks.
//

@preconcurrency import AVFoundation
import Foundation

public struct FrameGrabber: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func duration() async throws -> Double { try await AVURLAsset(url: url).load(.duration).seconds }

    /// The frame at `seconds`, at most `maxSize` (aspect kept).
    public func image(at seconds: Double, maxSize: CGSize? = nil) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        if let maxSize { generator.maximumSize = maxSize }
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    /// The frame at a fraction of the length (0.18 is 18 %).
    public func image(atFraction fraction: Double, maxSize: CGSize? = nil) async throws -> (CGImage, Double) {
        let length = try await duration()
        let t = min(max(0, length * fraction), max(0, length - 1.0 / 30))
        return (try await image(at: t, maxSize: maxSize), t)
    }
}
