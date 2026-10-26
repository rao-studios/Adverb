//
//  MusicChoice.swift
//  AdverbCore
//
//  WHAT: The song an asset was re-cut to and how: where it starts in the song, the grid used, how
//        the page met the beat (warped, or re-timed by Claude), fade and gain.
//

import Foundation

public enum BeatmapMode: String, Codable, Sendable, CaseIterable, Hashable {
    /// Scene boundaries move to downbeats by a time warp, and the kit adds beat accents. No Claude call.
    case warp
    /// Claude rewrites the page's timing against the beat list; validated before it renders.
    case retime

    public var title: String { self == .warp ? "Warp to the beat" : "Re-time with Claude" }
}

public struct MusicChoice: Codable, Sendable, Equatable, Hashable {
    public var songPath: String
    public var songSHA: String
    public var title: String
    public var artist: String?
    public var bpm: Double
    public var confidence: Double
    /// Seconds into the song where the asset starts.
    public var inPoint: Double
    public var fadeOut: Double
    public var gainDB: Double
    /// 1, 2 (double time) or 0.5 (half time): the octave the person picked.
    public var octave: Double
    /// Whole beats the downbeat was nudged by.
    public var phaseNudge: Int
    public var mode: BeatmapMode
    public var appliedAt: Date

    public init(songPath: String, songSHA: String, title: String, artist: String? = nil, bpm: Double, confidence: Double,
                inPoint: Double, fadeOut: Double = 1.2, gainDB: Double = -3, octave: Double = 1, phaseNudge: Int = 0,
                mode: BeatmapMode = .warp, appliedAt: Date = Date()) {
        self.songPath = songPath; self.songSHA = songSHA; self.title = title; self.artist = artist; self.bpm = bpm
        self.confidence = confidence; self.inPoint = inPoint; self.fadeOut = fadeOut; self.gainDB = gainDB
        self.octave = octave; self.phaseNudge = phaseNudge; self.mode = mode; self.appliedAt = appliedAt
    }

    public var credit: String { artist.map { "\(title) — \($0)" } ?? title }
}
