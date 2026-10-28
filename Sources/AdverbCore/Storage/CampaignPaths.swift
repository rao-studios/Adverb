//
//  CampaignPaths.swift
//  AdverbCore
//
//  WHAT: Every path in a campaign folder, named once:
//        campaigns/<id>/{campaign.json, context-digest.md, 00-series-overview.jpg, exports/, logs/,
//        assets/NN-topic/{page.html, NN-topic-portrait.mp4, NN-topic-landscape.mp4, sheet.jpg,
//        stills/, NN-topic-<orientation>.{vtt,srt}, NN-topic.descriptions.vtt, NN-topic.transcript.md,
//        NN-topic.beats.js, NN-topic-<orientation>.screen.vtt (a narrated asset's on-screen text),
//        voice/<code>/{script.json, line-NN.mp3}, and per other language NN-topic-<orientation>.<code>.mp4,
//        NN-topic-<orientation>.<code>.{vtt,srt}, NN-topic.<code>.transcript.md, original/, retimes/}}.
//

import Foundation

public struct CampaignPaths: Sendable, Equatable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public init(workspace: Workspace, projectSlug: String, campaignID: UUID) {
        root = workspace.projectFolder(projectSlug).appendingPathComponent("campaigns/\(campaignID.uuidString.lowercased())", isDirectory: true)
    }

    public var campaignFile: URL { root.appendingPathComponent("campaign.json") }
    public var digestFile: URL { root.appendingPathComponent("context-digest.md") }
    public var overview: URL { root.appendingPathComponent("00-series-overview.jpg") }
    public var exports: URL { root.appendingPathComponent("exports", isDirectory: true) }
    public var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }
    public var assets: URL { root.appendingPathComponent("assets", isDirectory: true) }

    public func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }

    public func relative(_ url: URL) -> String {
        let base = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    public func asset(_ stem: String) -> AssetPaths { AssetPaths(folder: assets.appendingPathComponent(stem, isDirectory: true), stem: stem) }
}

public struct AssetPaths: Sendable, Equatable {
    public let folder: URL
    public let stem: String

    public var page: URL { folder.appendingPathComponent("page.html") }
    public func video(_ o: Orientation) -> URL { folder.appendingPathComponent("\(stem)-\(o.rawValue).mp4") }
    public func vtt(_ o: Orientation) -> URL { folder.appendingPathComponent("\(stem)-\(o.rawValue).vtt") }
    public func srt(_ o: Orientation) -> URL { folder.appendingPathComponent("\(stem)-\(o.rawValue).srt") }
    public var descriptions: URL { folder.appendingPathComponent("\(stem).descriptions.vtt") }
    public var transcript: URL { folder.appendingPathComponent("\(stem).transcript.md") }
    public var beats: URL { folder.appendingPathComponent("\(stem).beats.js") }
    public var sheet: URL { folder.appendingPathComponent("sheet.jpg") }
    public var stills: URL { folder.appendingPathComponent("stills", isDirectory: true) }
    public func still(_ o: Orientation, _ t: Double) -> URL {
        stills.appendingPathComponent(String(format: "%@-%@_%05.2f.jpg", stem, o.letter, t))
    }
    public var original: URL { folder.appendingPathComponent("original", isDirectory: true) }
    public var retimes: URL { folder.appendingPathComponent("retimes", isDirectory: true) }

    // MARK: - Voice-over

    public var voice: URL { folder.appendingPathComponent("voice", isDirectory: true) }
    public func voice(_ l: Language) -> URL { voice.appendingPathComponent(l.code, isDirectory: true) }
    public func script(_ l: Language) -> URL { voice(l).appendingPathComponent("script.json") }
    public func clip(_ l: Language, _ line: Int) -> URL { voice(l).appendingPathComponent(String(format: "line-%02d.mp3", line)) }
    /// A narrated asset's on-screen text cues (its shipped captions carry the speech).
    public func screenVTT(_ o: Orientation) -> URL { folder.appendingPathComponent("\(stem)-\(o.rawValue).screen.vtt") }
    /// English is the asset's own files; another language gets `.<code>` before the extension.
    public func video(_ o: Orientation, _ l: Language) -> URL {
        l == .english ? video(o) : folder.appendingPathComponent("\(stem)-\(o.rawValue).\(l.code).mp4")
    }
    public func vtt(_ o: Orientation, _ l: Language) -> URL {
        l == .english ? vtt(o) : folder.appendingPathComponent("\(stem)-\(o.rawValue).\(l.code).vtt")
    }
    public func srt(_ o: Orientation, _ l: Language) -> URL {
        l == .english ? srt(o) : folder.appendingPathComponent("\(stem)-\(o.rawValue).\(l.code).srt")
    }
    public func transcript(_ l: Language) -> URL {
        l == .english ? transcript : folder.appendingPathComponent("\(stem).\(l.code).transcript.md")
    }
}
