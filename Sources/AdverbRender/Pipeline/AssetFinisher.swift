//
//  AssetFinisher.swift
//  AdverbRender
//
//  WHAT: The part of building an asset that is not Claude's: from a page on disk to stills, the
//        portrait and landscape MP4s, closed captions for each (WebVTT and SRT, from what the
//        render showed), the descriptions track, the transcript, the accessibility checks and the
//        contact sheet. A beatmapped re-cut runs the same steps with a song and a time warp.
//  PIN:  Silent renders are moved to original/ the first time music replaces them, with their
//        caption files, and never overwritten after: revert copies them back.
//

import AdverbCore
import Foundation

public struct FinishInput: Sendable {
    public var paths: CampaignPaths
    public var assetPaths: AssetPaths
    /// The project folder: everything the page may read (its kit).
    public var readAccess: URL
    public var day: CampaignDay
    public var html: String
    public var notes: AssetNotes
    public var altText: String
    /// Descriptions in page time; mapped through the warp for a beatmapped render.
    public var descriptions: [Cue]
    public var scale: Int
    public var bitrate: Int
    public var music: MusicChoice?
    public var mix: AudioMixSpec?
    public var warp: TimeWarp?
    public var previous: Asset?
    public var runID: UUID?
    /// Which renderer paints the frames; the encoder, audio and captions are the same either way.
    public var renderer: RendererKind = .native
    /// The project's kit folder (the Chrome renderer runs its script from there).
    public var kit: URL?

    public init(paths: CampaignPaths, assetPaths: AssetPaths, readAccess: URL, day: CampaignDay, html: String, notes: AssetNotes,
                altText: String, descriptions: [Cue], scale: Int = 1, bitrate: Int = 12_000_000, music: MusicChoice? = nil,
                mix: AudioMixSpec? = nil, warp: TimeWarp? = nil, previous: Asset? = nil, runID: UUID? = nil) {
        self.paths = paths; self.assetPaths = assetPaths; self.readAccess = readAccess; self.day = day; self.html = html
        self.notes = notes; self.altText = altText; self.descriptions = descriptions; self.scale = scale; self.bitrate = bitrate
        self.music = music; self.mix = mix; self.warp = warp; self.previous = previous; self.runID = runID
    }
}

public enum FinishStep: String, Sendable {
    case stills = "Stills", renderPortrait = "Portrait", renderLandscape = "Landscape", captions = "Captions", sheet = "Contact sheet"
}

@MainActor
public enum AssetFinisher {
    public static let stillFractions: [Double] = [0.18, 0.42, 0.66, 0.97]

    /// Stills at 18/42/66/97 % in both orientations, named as the skill names them.
    public static func stills(_ input: FinishInput) async throws -> [Still] {
        let duration = Double(input.day.topic.duration)
        let times = stillFractions.map { (duration * $0 * 100).rounded() / 100 }
        var out: [Still] = []
        for o in Orientation.allCases {
            let urls = times.map { input.assetPaths.still(o, $0) }
            if input.renderer == .chrome, let kit = input.kit {
                try await ChromeRenderer.stills(page: input.assetPaths.page, kit: kit, orientation: o, times: times, to: urls, warp: input.warp)
            } else {
                _ = try await PageRenderer.stills(page: input.assetPaths.page, readAccess: input.readAccess, orientation: o, times: times,
                                                  to: urls, warp: input.warp)
            }
            out += zip(times, urls).map { Still(orientation: o, time: $0, path: input.paths.relative($1)) }
        }
        return out
    }

    /// Everything after the page: renders, captions, descriptions, transcript, checks, sheet.
    public static func finish(_ input: FinishInput, stills: [Still],
                              progress: @escaping @Sendable (FinishStep, Double) -> Void = { _, _ in },
                              isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }) async throws -> Asset {
        let a = input.assetPaths
        let duration = Double(input.day.topic.duration)
        var asset = input.previous ?? Asset(folder: input.paths.relative(a.folder), duration: input.day.topic.duration,
                                            pagePath: input.paths.relative(a.page))
        asset.duration = input.day.topic.duration
        asset.pagePath = input.paths.relative(a.page)
        asset.stills = stills
        asset.notes = input.notes

        // First music on this asset: keep the silent originals, with their captions.
        if input.music != nil, asset.originals.isEmpty, !asset.renders.isEmpty {
            asset.originals = try keepOriginals(asset, input: input)
            asset.originalA11y = asset.a11y
        }

        let options = { (o: Orientation) in
            RenderOptions(scale: input.scale, encoder: EncoderSettings(bitrate: input.bitrate), mix: input.mix, warp: input.warp, captionEvery: 3)
        }
        var renders: [Render] = []
        var captions: [Orientation: [Cue]] = [:]
        for o in Orientation.allCases {
            let step: FinishStep = o == .portrait ? .renderPortrait : .renderLandscape
            let output: RenderOutput
            if input.renderer == .chrome, let kit = input.kit {
                output = try await ChromeRenderer.render(page: a.page, kit: kit, orientation: o, to: a.video(o), options: options(o), duration: duration,
                                                         progress: { progress(step, $0) }, isCancelled: isCancelled)
            } else {
                output = try await PageRenderer.render(page: a.page, readAccess: input.readAccess, orientation: o, to: a.video(o),
                                                       options: options(o), duration: duration,
                                                       progress: { progress(step, $0) }, isCancelled: isCancelled)
            }
            renders.append(Render(orientation: o, path: input.paths.relative(a.video(o)), seconds: output.report.duration,
                                  renderer: input.renderer == .chrome ? "chrome" : "wk", report: output.report))
            captions[o] = CueTracker.captions(from: output.captions, step: 0.1, duration: duration)
        }
        asset.renders = renders

        progress(.captions, 0)
        let music = input.music?.credit
        let descriptions = input.descriptions.map { cue -> Cue in
            guard let warp = input.warp else { return cue }
            return Cue(start: warp.realTime(forPage: cue.start), end: warp.realTime(forPage: cue.end), text: cue.text, kind: .description)
        }
        let pageStrings = A11yChecker.pageStrings(html: input.html)
        var files: [String: CaptionFiles] = [:]
        for o in Orientation.allCases {
            let cues = CueTracker.withMusic(captions[o] ?? [], credit: music, duration: duration)
            try AtomicFile.write(WebVTTWriter.write(cues, title: input.day.topic.title), to: a.vtt(o))
            try AtomicFile.write(SRTWriter.write(cues), to: a.srt(o))
            files[o.rawValue] = CaptionFiles(vtt: input.paths.relative(a.vtt(o)), srt: input.paths.relative(a.srt(o)), cueCount: cues.count,
                                             coverage: A11yChecker.coverage(of: pageStrings, in: captions[o] ?? []))
        }
        try AtomicFile.write(WebVTTWriter.write(descriptions, kind: .descriptions, title: input.day.topic.title), to: a.descriptions)
        try AtomicFile.write(TranscriptWriter.write(title: input.day.topic.title, captions: captions[.portrait] ?? [], descriptions: descriptions,
                                                    altText: input.altText, music: music), to: a.transcript)
        let scenes = PageVerifier.scenes(input.html).map { s in input.warp.map { $0.realTime(forPage: s) } ?? s }
        asset.a11y = A11y(altText: input.altText, descriptions: descriptions, captions: files,
                          descriptionsPath: input.paths.relative(a.descriptions), transcriptPath: input.paths.relative(a.transcript),
                          checks: A11yChecker.check(captions: captions, descriptions: descriptions, scenes: scenes, duration: duration,
                                                    altText: input.altText, platforms: input.day.targets.map(\.platform), pageStrings: pageStrings))
        progress(.captions, 1)

        progress(.sheet, 0)
        try await ContactSheet.make(portrait: a.video(.portrait), landscape: a.video(.landscape), title: input.day.stem,
                                    duration: input.day.topic.duration, to: a.sheet)
        asset.sheetPath = input.paths.relative(a.sheet)
        progress(.sheet, 1)

        asset.music = input.music
        asset.builtAt = Date()
        asset.buildRunID = input.runID
        return asset
    }

    /// Copies the silent page, renders and caption files into original/, once.
    static func keepOriginals(_ asset: Asset, input: FinishInput) throws -> [Render] {
        let a = input.assetPaths
        let fm = FileManager.default
        try fm.createDirectory(at: a.original, withIntermediateDirectories: true)
        var kept: [Render] = []
        var files = [a.page, a.descriptions, a.transcript]
        for o in Orientation.allCases { files += [a.vtt(o), a.srt(o)] }
        for file in files where fm.fileExists(atPath: file.path) {
            try AtomicFile.replace(a.original.appendingPathComponent(file.lastPathComponent), with: file)
        }
        for render in asset.renders {
            let source = input.paths.url(render.path)
            guard fm.fileExists(atPath: source.path) else { continue }
            let dest = a.original.appendingPathComponent(source.lastPathComponent)
            try AtomicFile.replace(dest, with: source)
            var r = render
            r.path = input.paths.relative(dest)
            kept.append(r)
        }
        return kept
    }

    /// Puts the silent originals back: page, renders, captions. The asset loses its music.
    public static func revert(_ asset: Asset, paths: CampaignPaths, assetPaths a: AssetPaths) throws -> Asset {
        guard !asset.originals.isEmpty else { return asset }
        let fm = FileManager.default
        for file in AtomicFile.contents(of: a.original) where !AtomicFile.isDirectory(file) {
            try AtomicFile.replace(a.folder.appendingPathComponent(file.lastPathComponent), with: file)
        }
        try? fm.removeItem(at: a.beats)
        var out = asset
        out.renders = asset.originals.map { r in
            var c = r
            c.path = paths.relative(a.folder.appendingPathComponent(URL(fileURLWithPath: r.path).lastPathComponent))
            return c
        }
        out.music = nil
        if let original = asset.originalA11y { out.a11y = original }
        out.originals = []
        out.originalA11y = nil
        return out
    }
}
