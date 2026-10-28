//
//  VoiceFinisher.swift
//  AdverbRender
//
//  WHAT: A voice-over put onto videos that already exist: the English narration remuxed onto an
//        asset's renders (a voice added to a built day, another voice, a revert), and each other
//        language remuxed from the English renders onto its own MP4s, with its captions and
//        transcript. No frame is rendered again; the sound is mixed fresh each time from the
//        cached clips, the music and the warp.
//  PIN:  A narrated asset's shipped captions carry the speech; its on-screen text lives in
//        NN-topic-<o>.screen.vtt (and the transcript's Text lines), written the first time a voice
//        replaces it.
//

import AdverbCore
import Foundation

public struct NarrationInput: Sendable, Equatable {
    public var voice: VoiceSelection
    public var lines: [NarrationLine]
    /// voice/en/script.json, relative to the campaign folder.
    public var scriptPath: String

    public init(voice: VoiceSelection, lines: [NarrationLine], scriptPath: String) {
        self.voice = voice; self.lines = lines; self.scriptPath = scriptPath
    }
}

public struct VoiceApplyInput: Sendable {
    public var paths: CampaignPaths
    public var assetPaths: AssetPaths
    public var day: CampaignDay
    /// The song under the renders, if any: mixed back under the voice.
    public var music: MusicChoice?
    /// Original page time → video time (the asset's warp).
    public var warp: TimeWarp?
    public var progress: @Sendable (String, Double) -> Void

    public init(paths: CampaignPaths, assetPaths: AssetPaths, day: CampaignDay, music: MusicChoice?, warp: TimeWarp?,
                progress: @escaping @Sendable (String, Double) -> Void = { _, _ in }) {
        self.paths = paths; self.assetPaths = assetPaths; self.day = day; self.music = music; self.warp = warp; self.progress = progress
    }
}

public struct NarrationCaptionFiles: Sendable {
    public var files: [String: CaptionFiles]
    public var transcriptPath: String
    /// The shipped cues (split, held, trimmed).
    public var cues: [Cue]
    /// One per line, as spoken.
    public var spoken: [Cue]
}

public enum VoiceFinisher {

    // MARK: - Sound

    public static func layer(lines: [NarrationLine], paths: CampaignPaths, warp: TimeWarp?) -> VoiceLayer {
        VoiceLayer(clips: lines.compactMap { line in
            guard let clip = line.clipPath else { return nil }
            return VoiceClip(url: paths.url(clip), startReal: line.placedStart(warp: warp))
        })
    }

    /// The song (when there is one) and the narration over it, for `duration` seconds.
    public static func mix(music: MusicChoice?, lines: [NarrationLine], paths: CampaignPaths, warp: TimeWarp?, duration: Double) -> AudioMixSpec {
        let voice = layer(lines: lines, paths: paths, warp: warp)
        guard let music else { return AudioMixSpec(voice: voice, duration: duration) }
        var spec = AudioMixSpec(song: URL(fileURLWithPath: music.songPath), inPoint: music.inPoint, duration: duration,
                                fadeOut: music.fadeOut, gainDB: music.gainDB)
        spec.voice = voice
        return spec
    }

    // MARK: - Captions

    /// The narration's captions (VTT and SRT per orientation, in its language) and transcript.
    public static func writeCaptions(lines: [NarrationLine], language: Language, warp: TimeWarp?, duration: Double, music: String?,
                                     screen: [Orientation: [Cue]], descriptions: [Cue], altText: String, title: String,
                                     scenes: [Double], paths: CampaignPaths, assetPaths a: AssetPaths) throws -> NarrationCaptionFiles {
        let cues = NarrationCaptions.cues(lines: lines, warp: warp, duration: duration)
        let spoken = NarrationCaptions.spoken(lines, warp: warp)
        let coverage = NarrationCaptions.coverage(scenes: scenes, cues: spoken, duration: duration)
        var files: [String: CaptionFiles] = [:]
        for o in Orientation.allCases {
            let shipped = CueTracker.withMusic(cues, credit: music, duration: duration)
            try AtomicFile.write(WebVTTWriter.write(shipped, language: language.code, title: title), to: a.vtt(o, language))
            try AtomicFile.write(SRTWriter.write(shipped), to: a.srt(o, language))
            files[o.rawValue] = CaptionFiles(vtt: paths.relative(a.vtt(o, language)), srt: paths.relative(a.srt(o, language)),
                                             cueCount: shipped.count, coverage: coverage)
        }
        try AtomicFile.write(TranscriptWriter.write(title: title, captions: screen[.portrait] ?? [], descriptions: descriptions,
                                                    altText: altText, music: music, said: spoken), to: a.transcript(language))
        return NarrationCaptionFiles(files: files, transcriptPath: paths.relative(a.transcript(language)), cues: cues, spoken: spoken)
    }

    /// The on-screen text cues: the sidecar if a voice has already replaced them, else the
    /// shipped captions (a silent asset's), kept in the sidecar from now on.
    public static func screenCues(_ a: AssetPaths) throws -> [Orientation: [Cue]] {
        var out: [Orientation: [Cue]] = [:]
        for o in Orientation.allCases {
            if let text = try? String(contentsOf: a.screenVTT(o), encoding: .utf8) {
                out[o] = WebVTTReader.parse(text)
            } else {
                let shipped = ((try? String(contentsOf: a.vtt(o), encoding: .utf8)).map(WebVTTReader.parse) ?? []).filter { !$0.text.hasPrefix("[♪") }
                try AtomicFile.write(WebVTTWriter.write(shipped), to: a.screenVTT(o))
                out[o] = shipped
            }
        }
        return out
    }

    /// Scene starts in video time: the original page's scenes through the warp.
    public static func scenes(_ a: AssetPaths, warp: TimeWarp?) -> [Double] {
        let original = a.original.appendingPathComponent("page.html")
        let page = (try? String(contentsOf: FileManager.default.fileExists(atPath: original.path) && warp != nil ? original : a.page, encoding: .utf8)) ?? ""
        return PageVerifier.scenes(page).map { s in warp.map { $0.realTime(forPage: s) } ?? s }
    }

    // MARK: - English

    /// The English narration onto the asset's current renders, its captions, transcript and
    /// checks. When the voice or the words changed, the confirmation goes and the language
    /// tracks lose their videos (their translated lines stay; their clips too, unless the voice
    /// changed).
    public static func applyEnglish(_ asset: Asset, selection: VoiceSelection, lines: [NarrationLine], scriptPath: String,
                                    input: VoiceApplyInput) async throws -> Asset {
        var out = asset
        let a = input.assetPaths
        let duration = Double(asset.duration)
        let screen = try screenCues(a)
        let mix = mix(music: input.music, lines: lines, paths: input.paths, warp: input.warp, duration: duration)
        var renders: [Render] = []
        for (i, render) in asset.renders.enumerated() {
            input.progress("Mixing the voice-over", Double(i) / Double(max(1, asset.renders.count)))
            let url = input.paths.url(render.path)
            let report = try await AudioRemux.replaceAudio(in: url, mix: mix, to: url, expecting: (duration, render.orientation))
            var r = render
            r.report = report; r.renderedAt = Date(); r.seconds = report.duration
            renders.append(r)
        }
        out.renders = renders
        input.progress("Captions", 0)
        let scenes = scenes(a, warp: input.warp)
        let page = (try? String(contentsOf: a.page, encoding: .utf8)) ?? ""
        let captions = try writeCaptions(lines: lines, language: .english, warp: input.warp, duration: duration, music: input.music?.credit,
                                         screen: screen, descriptions: asset.a11y.descriptions, altText: asset.a11y.altText,
                                         title: input.day.topic.title, scenes: scenes, paths: input.paths, assetPaths: a)
        out.a11y.captions = captions.files
        out.a11y.transcriptPath = captions.transcriptPath
        out.a11y.checks = A11yChecker.check(captions: Dictionary(uniqueKeysWithValues: Orientation.allCases.map { ($0, captions.cues) }),
                                            descriptions: asset.a11y.descriptions, scenes: scenes, duration: duration,
                                            altText: asset.a11y.altText, platforms: input.day.targets.map(\.platform),
                                            pageStrings: A11yChecker.pageStrings(html: page), narration: captions.spoken)
        let english = VoiceTrack(language: .english, scriptPath: scriptPath, lines: lines, captions: captions.files,
                                 transcriptPath: captions.transcriptPath, characters: lines.reduce(0) { $0 + $1.characters })
        out.voiceOver = updated(asset.voiceOver, selection: selection, english: english, assetPaths: a, paths: input.paths)
        out.warp = input.warp
        input.progress("Captions", 1)
        return out
    }

    /// The voice-over with a new English track: what changed decides what the languages keep.
    static func updated(_ previous: VoiceOver?, selection: VoiceSelection, english: VoiceTrack, assetPaths a: AssetPaths, paths: CampaignPaths) -> VoiceOver {
        guard var vo = previous else { return VoiceOver(selection: selection, english: english) }
        let voiceChanged = vo.voiceID != selection.voiceID || vo.modelID != selection.modelID
        let wordsChanged = vo.english.lines.map(\.text) != english.lines.map(\.text)
        if voiceChanged || wordsChanged {
            vo.confirmedAt = nil
            vo.languages = vo.languages.map { track in
                var t = track
                removeFiles(of: t.language, assetPaths: a)
                t.renders = []; t.captions = [:]; t.transcriptPath = nil
                if wordsChanged { t.stale = true }
                if voiceChanged {
                    for line in t.lines { if let clip = line.clipPath { try? FileManager.default.removeItem(at: paths.url(clip)) } }
                    t.lines = t.lines.map { var l = $0; l.clipPath = nil; l.spokenStart = nil; l.spokenEnd = nil; l.words = []; l.requestID = nil; l.cacheKey = nil; return l }
                }
                return t
            }
        }
        vo.voiceID = selection.voiceID; vo.voiceName = selection.voiceName; vo.modelID = selection.modelID; vo.settings = selection.settings
        vo.english = english
        vo.appliedAt = Date()
        return vo
    }

    public static func removeFiles(of language: Language, assetPaths a: AssetPaths) {
        guard language != .english else { return }
        let fm = FileManager.default
        for o in Orientation.allCases { for url in [a.video(o, language), a.vtt(o, language), a.srt(o, language)] { try? fm.removeItem(at: url) } }
        try? fm.removeItem(at: a.transcript(language))
    }

    // MARK: - Languages

    /// Each language track whose lines are all recorded, remuxed from the English renders onto
    /// its own MP4s with its captions and transcript. `only` limits which.
    public static func deriveLanguages(_ asset: Asset, only: [Language]? = nil, input: VoiceApplyInput) async throws -> Asset {
        guard var vo = asset.voiceOver else { return asset }
        let a = input.assetPaths
        let duration = Double(asset.duration)
        let screen = try screenCues(a)
        let scenes = scenes(a, warp: input.warp)
        let fm = FileManager.default
        for (index, track) in vo.languages.enumerated() where only?.contains(track.language) ?? true {
            let recorded = !track.lines.isEmpty && track.lines.allSatisfy { l in l.clipPath.map { fm.fileExists(atPath: input.paths.url($0).path) } ?? false }
            guard recorded else { continue }
            let label = "Mixing \(track.language.title)"
            let mix = mix(music: input.music, lines: track.lines, paths: input.paths, warp: input.warp, duration: duration)
            var renders: [Render] = []
            for (i, english) in asset.renders.enumerated() {
                input.progress(label, Double(i) / Double(max(1, asset.renders.count)))
                let dest = a.video(english.orientation, track.language)
                let report = try await AudioRemux.replaceAudio(in: input.paths.url(english.path), mix: mix, to: dest,
                                                               expecting: (duration, english.orientation))
                renders.append(Render(orientation: english.orientation, path: input.paths.relative(dest), seconds: report.duration,
                                      renderer: english.renderer, report: report))
            }
            let captions = try writeCaptions(lines: track.lines, language: track.language, warp: input.warp, duration: duration,
                                             music: input.music?.credit, screen: screen, descriptions: asset.a11y.descriptions,
                                             altText: asset.a11y.altText, title: input.day.topic.title, scenes: scenes,
                                             paths: input.paths, assetPaths: a)
            var t = track
            t.renders = renders; t.captions = captions.files; t.transcriptPath = captions.transcriptPath
            t.characters = track.lines.reduce(0) { $0 + $1.characters }
            t.generatedAt = Date()
            vo.languages[index] = t
            input.progress(label, 1)
        }
        var out = asset
        out.voiceOver = vo
        return out
    }
}
