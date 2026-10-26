//
//  RenderReport.swift
//  AdverbCore
//
//  WHAT: What an MP4 turned out to be (what ffprobe used to answer): length, frames, size,
//        bitrate, audio, faststart, and whatever did not match what was asked for.
//

import Foundation

public struct RenderReport: Codable, Sendable, Equatable, Hashable {
    public var duration: Double
    public var frameCount: Int
    public var fps: Double
    public var width: Int
    public var height: Int
    /// Video bits per second.
    public var bitrate: Double
    public var hasAudio: Bool
    public var audio: String?
    public var fastStart: Bool
    /// Wall-clock seconds the render took.
    public var renderSeconds: Double?
    public var warnings: [String]

    public init(duration: Double, frameCount: Int, fps: Double, width: Int, height: Int, bitrate: Double, hasAudio: Bool,
                audio: String?, fastStart: Bool, renderSeconds: Double? = nil, warnings: [String] = []) {
        self.duration = duration; self.frameCount = frameCount; self.fps = fps; self.width = width; self.height = height
        self.bitrate = bitrate; self.hasAudio = hasAudio; self.audio = audio; self.fastStart = fastStart
        self.renderSeconds = renderSeconds; self.warnings = warnings
    }

    /// "15.00 s · 450 frames · 1080×1920 · 9.8 Mbps · AAC · faststart"
    public var line: String {
        var parts = [String(format: "%.2f s", duration), "\(frameCount) frames", "\(width)×\(height)", String(format: "%.1f Mbps", bitrate / 1_000_000)]
        if hasAudio { parts.append(audio ?? "audio") }
        if fastStart { parts.append("faststart") }
        return parts.joined(separator: " · ")
    }

    public var isClean: Bool { warnings.isEmpty }
}
