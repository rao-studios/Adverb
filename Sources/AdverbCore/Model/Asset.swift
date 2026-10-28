//
//  Asset.swift
//  AdverbCore
//
//  WHAT: A built asset: its page, its two renders (and the silent originals once music replaced
//        them), stills, the contact sheet, what Claude said about accuracy, the accessibility files,
//        the music, when there is some, and the voice-over with its languages.
//  PIN:  Paths are relative to the campaign folder, so a campaign folder moved with its drive
//        still opens.
//

import Foundation

public struct Asset: Codable, Sendable, Equatable, Hashable {
    /// "assets/03-highlight"
    public var folder: String
    public var duration: Int
    /// "assets/03-highlight/page.html"
    public var pagePath: String
    public var renders: [Render]
    /// The silent renders, kept in `original/` the first time music replaced them.
    public var originals: [Render]
    public var stills: [Still]
    public var sheetPath: String?
    public var notes: AssetNotes
    public var a11y: A11y
    /// The silent version's accessibility, kept beside `originals` for a revert.
    public var originalA11y: A11y?
    public var music: MusicChoice?
    /// The narration and its language tracks, when the asset is narrated.
    public var voiceOver: VoiceOver?
    /// Original page time → video time, kept when a re-cut moved the scenes, so a language track
    /// made later places its clips where the English ones landed.
    public var warp: TimeWarp?
    public var reviewed: Bool
    public var builtAt: Date
    public var buildRunID: UUID?

    public init(folder: String, duration: Int, pagePath: String, renders: [Render] = [], originals: [Render] = [],
                stills: [Still] = [], sheetPath: String? = nil, notes: AssetNotes = .init(), a11y: A11y = .init(),
                music: MusicChoice? = nil, voiceOver: VoiceOver? = nil, warp: TimeWarp? = nil, reviewed: Bool = false,
                builtAt: Date = Date(), buildRunID: UUID? = nil) {
        self.folder = folder; self.duration = duration; self.pagePath = pagePath; self.renders = renders
        self.originals = originals; self.stills = stills; self.sheetPath = sheetPath; self.notes = notes
        self.a11y = a11y; self.originalA11y = nil; self.music = music; self.voiceOver = voiceOver; self.warp = warp; self.reviewed = reviewed; self.builtAt = builtAt; self.buildRunID = buildRunID
    }

    public func render(_ orientation: Orientation) -> Render? { renders.first { $0.orientation == orientation } }
    public func stills(_ orientation: Orientation) -> [Still] { stills.filter { $0.orientation == orientation } }
}

public struct Render: Codable, Sendable, Equatable, Hashable {
    public var orientation: Orientation
    /// Relative to the campaign folder.
    public var path: String
    public var seconds: Double
    public var renderedAt: Date
    /// "wk" (the native renderer) or "chrome" (Playwright).
    public var renderer: String
    public var report: RenderReport?

    public init(orientation: Orientation, path: String, seconds: Double, renderedAt: Date = Date(), renderer: String = "wk", report: RenderReport? = nil) {
        self.orientation = orientation; self.path = path; self.seconds = seconds; self.renderedAt = renderedAt
        self.renderer = renderer; self.report = report
    }
}

public struct Still: Codable, Sendable, Equatable, Hashable {
    public var orientation: Orientation
    public var time: Double
    public var path: String

    public init(orientation: Orientation, time: Double, path: String) {
        self.orientation = orientation; self.time = time; self.path = path
    }
}

/// rao-motion-assets §3 rule 8: what is illustrative and what was softened, said with the asset.
public struct AssetNotes: Codable, Sendable, Equatable, Hashable {
    public var summary: String
    public var illustrative: [String]
    public var softened: [String]
    public var sources: [String]

    public init(summary: String = "", illustrative: [String] = [], softened: [String] = [], sources: [String] = []) {
        self.summary = summary; self.illustrative = illustrative; self.softened = softened; self.sources = sources
    }
}
