//
//  RetimeJob.swift
//  AdverbAgents
//
//  WHAT: Re-cuts a day's asset to a song. The grid is re-read on the segment used (in-point to
//        in-point + DUR) and corrected by the person's octave and downbeat nudge; then the page
//        meets the beat — warped (scene starts to downbeats, no Claude call) or re-timed by Claude
//        (validated; a failed re-time falls back to the warp) — and both orientations render with
//        the song under them (and the voice-over over it, ducking it, with every language re-mixed).
//        The silent originals are kept for a revert.
//  PIN:  Every re-cut starts from the silent original page, never from a previous re-cut.
//

import AdverbCore
import AdverbRender
import Foundation

public struct RetimeRequest: Sendable, Equatable {
    public var song: URL
    public var title: String
    public var artist: String?
    public var inPoint: Double
    public var octave: Double
    public var phaseNudge: Int
    public var gainDB: Double
    public var fadeOut: Double
    public var mode: BeatmapMode

    public init(song: URL, title: String, artist: String? = nil, inPoint: Double, octave: Double = 1, phaseNudge: Int = 0,
                gainDB: Double = -3, fadeOut: Double = 1.2, mode: BeatmapMode = .warp) {
        self.song = song; self.title = title; self.artist = artist; self.inPoint = inPoint; self.octave = octave
        self.phaseNudge = phaseNudge; self.gainDB = gainDB; self.fadeOut = fadeOut; self.mode = mode
    }
}

public enum RetimeJob {
    public static func run(projectSlug: String, campaignID: UUID, dayIndex: Int, request: RetimeRequest, compute: AdverbCompute,
                           emit: @escaping @Sendable (GenerationEvent) -> Void) async throws {
        let project = try compute.project(projectSlug)
        let paths = compute.paths(project, campaignID)
        let log = RunLog(paths: paths, campaignID: campaignID, kind: .beatmap(day: dayIndex), model: compute.settings.model)
        do {
            let campaign = try await CampaignLedger.shared.read(paths)
            guard let day = campaign.day(dayIndex), let asset = day.asset else { throw CampaignError.noDay(dayIndex) }
            let a = paths.asset(day.stem)
            let kit = compute.kitFolder(project)
            let readAccess = compute.workspace.projectFolder(project.slug)
            let duration = Double(day.topic.duration)
            log.line("\(request.title) from \(String(format: "%.2f", request.inPoint)) s · \(request.mode.rawValue)")

            emit(.step("Finding the beat"))
            log.step("Finding the beat", day: dayIndex)
            let grid = try await BeatAnalyzer.shared.analyzeWindow(request.song, inPoint: request.inPoint, duration: duration)
                .adjusted(octave: request.octave, phaseNudge: request.phaseNudge)
            log.line(String(format: "%.1f BPM · confidence %.2f · %d beats, %d downbeats%@", grid.bpm, grid.confidence, grid.beats.count,
                            grid.downbeats.count, grid.nominal ? " · nominal grid" : ""))

            // The silent original page is the base for every re-cut.
            let originalPage = a.original.appendingPathComponent("page.html")
            let current = try String(contentsOf: a.page, encoding: .utf8)
            let base = (try? String(contentsOf: originalPage, encoding: .utf8)) ?? current
            let scenes = PageVerifier.scenes(base)
            let kitPrefix = PageVerifier.relativePath(from: a.folder, to: kit)
            var html = base
            var warp: TimeWarp? = Beatmap.warp(scenes: scenes, grid: grid, duration: duration, endAt: duration - 1.6)
            // Where the voice-over's lines land: the warp, or for a re-time, the scenes' move.
            var placement = warp
            var mode = request.mode
            var descriptions = asset.originalA11y?.descriptions ?? asset.a11y.descriptions

            if mode == .retime {
                emit(.step("Re-timing with Claude"))
                log.step("Re-timing with Claude", day: dayIndex)
                let r = ClaudeRequest(system: compute.prompts.system, messages: compute.prompts.retime(html: base, grid: grid, song: request.title),
                                      schema: Schemas.retime, maxTokens: 64_000)
                do {
                    let (retimed, _) = try await ClaudeCall.structured(RetimeResponse.self, client: compute.client, request: r, log: log, emit: emit)
                    let problems = RetimeValidator.problems(original: base, retimed: retimed.html, duration: day.topic.duration, grid: grid, cues: retimed.cues)
                    if problems.isEmpty {
                        let newScenes = PageVerifier.scenes(retimed.html)
                        // Descriptions follow the scenes from where they were to where they are now.
                        if newScenes.count == scenes.count, !scenes.isEmpty {
                            let moved = TimeWarp(knots: zip(scenes, newScenes).map { TimeWarp.Knot(page: $1, real: $0) } + [.init(page: duration, real: duration)])
                            descriptions = descriptions.map { Cue(start: moved.pageTime(forReal: $0.start), end: moved.pageTime(forReal: $0.end), text: $0.text, kind: .description) }
                        }
                        html = retimed.html
                        warp = nil
                        placement = newScenes.count == scenes.count && !scenes.isEmpty
                            ? TimeWarp(knots: zip(scenes, newScenes).map { TimeWarp.Knot(page: $0, real: $1) } + [.init(page: duration, real: duration)])
                            : nil
                    } else {
                        log.line("re-time kept out: \(problems.joined(separator: " | ")); warping instead")
                        emit(.log("Claude's re-time changed more than timing; warped instead."))
                        mode = .warp
                    }
                } catch let error as ClaudeError {
                    log.line("re-time failed: \(error); warping instead")
                    mode = .warp
                }
            }

            try AtomicFile.write(Beatmap.beatsScript(grid: grid, inPoint: request.inPoint, song: request.title), to: a.beats)
            html = Beatmap.withBeatScripts(html, kitPrefix: kitPrefix, beatsFile: a.beats.lastPathComponent)
            if let warp { log.line("warp: " + warp.knots.map { String(format: "%.2f→%.2f", $0.page, $0.real) }.joined(separator: ", ")) }

            // Keep the silent page before overwriting it (once), then write the beat page.
            if !FileManager.default.fileExists(atPath: originalPage.path) {
                try AtomicFile.replace(originalPage, with: a.page)
            }
            try AtomicFile.write(html, to: a.page)

            let choice = MusicChoice(songPath: request.song.path, songSHA: BeatAnalyzer.shared.cacheKey(request.song), title: request.title,
                                     artist: request.artist, bpm: grid.bpm, confidence: grid.confidence, inPoint: request.inPoint,
                                     fadeOut: request.fadeOut, gainDB: request.gainDB, octave: request.octave,
                                     phaseNudge: request.phaseNudge, mode: mode)
            var previous = asset
            if previous.originalA11y != nil { previous.a11y = previous.originalA11y! }
            var input = FinishInput(paths: paths, assetPaths: a, readAccess: readAccess, day: day, html: html, notes: asset.notes,
                                    altText: asset.a11y.altText, descriptions: descriptions,
                                    scale: compute.settings.supersample ? 2 : 1, bitrate: compute.settings.bitrateMbps * 1_000_000,
                                    music: choice, mix: AudioMixSpec(song: request.song, inPoint: request.inPoint, duration: duration,
                                                                    fadeOut: request.fadeOut, gainDB: request.gainDB),
                                    warp: warp, previous: previous, runID: log.id)
            input.renderer = compute.settings.renderer
            input.kit = kit
            input.placement = placement
            if let vo = asset.voiceOver, !vo.english.lines.isEmpty, vo.english.lines.allSatisfy(\.isRecorded) {
                input.narration = NarrationInput(voice: vo.selection, lines: vo.english.lines, scriptPath: vo.english.scriptPath)
            }
            emit(.step("Stills"))
            let finalInput = input
            let stills = try await AssetFinisher.stills(finalInput)
            emit(.step("Waiting to render"))
            var updated = try await RenderGate.shared.run {
                try await AssetFinisher.finish(finalInput, stills: stills, progress: { step, p in emit(.step(step.rawValue)); emit(.progress(p)) })
            }
            // The languages follow the new cut: their clips re-placed, the song under them.
            if let vo = updated.voiceOver, !vo.languages.isEmpty {
                let tell = StepTeller(emit)
                updated = try await VoiceFinisher.deriveLanguages(updated, input: VoiceApplyInput(paths: paths, assetPaths: a, day: day, music: choice,
                                                                                                  warp: placement, progress: { tell($0, $1) }))
            }
            for render in updated.renders { log.line("\(render.orientation.rawValue): \(render.report?.line ?? render.path)") }
            let recut = updated
            try await CampaignLedger.shared.updateDay(paths, index: dayIndex) { d in d.asset = recut; d.problem = nil }
            emit(.dayDone(dayIndex))
            log.finish(.succeeded)
        } catch is CancellationError {
            log.finish(.cancelled); throw CancellationError()
        } catch RenderError.cancelled {
            log.finish(.cancelled); throw CancellationError()
        } catch {
            emit(.problem("\(error)"))
            log.finish(.failed("\(error)"))
            throw error
        }
    }
}
