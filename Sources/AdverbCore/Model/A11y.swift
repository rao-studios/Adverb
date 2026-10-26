//
//  A11y.swift
//  AdverbCore
//
//  WHAT: An asset's accessibility: alt text, closed captions of the on-screen text per
//        orientation (WebVTT and SRT), a descriptions track, a transcript, and the checks it passed.
//  PIN:  Captions come from the render pass itself (what was visible, when), so their timing is
//        the video's, warped or not. Descriptions and alt text are Claude's, written with the page.
//

import Foundation

public struct Cue: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable { case text, description, music }
    public var start: Double
    public var end: Double
    public var text: String
    public var kind: Kind

    public init(start: Double, end: Double, text: String, kind: Kind = .text) {
        self.start = start; self.end = end; self.text = text; self.kind = kind
    }
}

public struct CaptionFiles: Codable, Sendable, Equatable, Hashable {
    /// Relative to the campaign folder.
    public var vtt: String
    public var srt: String
    public var cueCount: Int
    /// Share of the page's own text strings found in the cues, 0…1.
    public var coverage: Double

    public init(vtt: String, srt: String, cueCount: Int, coverage: Double) {
        self.vtt = vtt; self.srt = srt; self.cueCount = cueCount; self.coverage = coverage
    }
}

public struct A11yCheck: Codable, Sendable, Equatable, Hashable {
    public enum Level: String, Codable, Sendable, Hashable { case ok, warning, problem }
    public var level: Level
    public var message: String

    public init(_ level: Level, _ message: String) { self.level = level; self.message = message }
}

public struct A11y: Codable, Sendable, Equatable, Hashable {
    public var altText: String
    public var descriptions: [Cue]
    public var captions: [String: CaptionFiles]
    public var descriptionsPath: String?
    public var transcriptPath: String?
    public var checks: [A11yCheck]

    public init(altText: String = "", descriptions: [Cue] = [], captions: [String: CaptionFiles] = [:],
                descriptionsPath: String? = nil, transcriptPath: String? = nil, checks: [A11yCheck] = []) {
        self.altText = altText; self.descriptions = descriptions; self.captions = captions
        self.descriptionsPath = descriptionsPath; self.transcriptPath = transcriptPath; self.checks = checks
    }

    public func captions(_ orientation: Orientation) -> CaptionFiles? { captions[orientation.rawValue] }

    public var isComplete: Bool {
        !altText.isEmpty && captions.count == Orientation.allCases.count && descriptionsPath != nil && transcriptPath != nil
            && !checks.contains { $0.level == .problem }
    }
}
