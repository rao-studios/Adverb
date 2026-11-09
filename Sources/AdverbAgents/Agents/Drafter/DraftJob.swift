//
//  DraftJob.swift
//  AdverbAgents
//
//  WHAT: Writes one day to its contact sheet: the page (the writer, with the skill, the frozen digest
//        and the day's plan), checked statically and in the renderer (two rounds of fixes), the
//        voice-over when the campaign is narrated (the writer's lines, the voice on this Mac, the page
//        timed to it), the stills of both orientations, the sheet drawn from them, and the eyes' look
//        at the sheet (the writer fixes what they find, once). The day is then `sheeted`: judged from
//        its sheet before a frame of video is encoded (RenderJob makes the videos).
//  IN:   A note, when the person sent the sheet back: the page they saw is changed to do it.
//  PIN:  A day that fails says why on the day itself (`problem`), and the run fails with it; the
//        other days are untouched. A voice-over that fails does not fail the day: it finishes silent,
//        says why, and the voice can be added from the day later. A review that fails does not fail
//        it either: the sheet stands as it was written.
//  PIN:  Written again, a day loses its renders and its song: they were made from the page before.
//

import AdverbCore
import AdverbRender
import Foundation

public enum DraftJob {
    public static func run(projectSlug: String, campaignID: UUID, dayIndex: Int, note: String? = nil, compute: AdverbCompute,
                           emit: @escaping @Sendable (GenerationEvent) -> Void) async throws {
        var project = try compute.project(projectSlug)
        let paths = compute.paths(project, campaignID)
        let writer = compute.text
        let log = RunLog(paths: paths, campaignID: campaignID, kind: .draft(day: dayIndex), model: writer.info.id)
        do {
            let campaign = try await CampaignLedger.shared.read(paths)
            guard let day = campaign.day(dayIndex) else { throw CampaignError.noDay(dayIndex) }
            project = try ProjectStore(workspace: compute.workspace).ensureKit(project)
            let kit = compute.kitFolder(project)
            let a = paths.asset(day.stem)
            try FileManager.default.createDirectory(at: a.folder, withIntermediateDirectories: true)
            let readAccess = compute.workspace.projectFolder(project.slug)
            let digest = try compute.digest(project, paths: paths)
            let duration = day.topic.duration
            log.line("\(day.date) · \(day.topic.title) · \(duration) s · \(day.stem) · \(writer.info.title)")
            let note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            if let note { log.line("asked for: \(note)") }

            // 1. The page.
            emit(.step(note == nil ? "Writing the page" : "Changing the page"))
            log.step(note == nil ? "Writing the page" : "Changing the page", day: dayIndex)
            let base = compute.prompts.build(digest: digest.text, day: day, campaign: campaign, project: project)
            var turns = base
            if let note {
                if let previous = try? String(contentsOf: a.page, encoding: .utf8), !previous.isEmpty {
                    turns = compute.prompts.redo(previous: base, html: previous, note: note)
                } else {
                    turns = compute.prompts.build(digest: digest.text, day: day, campaign: campaign, project: project, note: note)
                }
            }
            let thinkingTokens = compute.thinking == .off ? 0 : compute.settings.thinkingBudget
            var request = ModelRequest(system: compute.prompts.system, turns: turns, format: Schemas.pageFormat,
                                       maxTokens: Self.pageTokens(duration) + thinkingTokens, thinking: compute.thinking, label: "page")
            var (page, answer) = try await ModelCall.structured(PageResponse.self, model: writer, request: request, log: log, emit: emit)
            var html = PageVerifier.rewriteKitPaths(page.html, pageFolder: a.folder, kitFolder: kit)
            var problems = try await check(html, at: a, readAccess: readAccess, duration: duration)
            var round = 0
            while !problems.isEmpty, round < 2 {
                round += 1
                emit(.step("Fixing the page"))
                log.step("Fixing (round \(round)): \(problems.joined(separator: " | "))", day: dayIndex)
                request.turns = compute.prompts.buildFix(previous: request.turns, answer: answer.text, problems: problems)
                request.thinking = .off
                request.maxTokens = Self.pageTokens(duration)
                (page, answer) = try await ModelCall.structured(PageResponse.self, model: writer, request: request, log: log, emit: emit)
                html = PageVerifier.rewriteKitPaths(page.html, pageFolder: a.folder, kitFolder: kit)
                problems = try await check(html, at: a, readAccess: readAccess, duration: duration)
            }
            guard problems.isEmpty else { throw ModelError.invalid("The page still breaks the contract: " + problems.joined(separator: " ")) }
            try AtomicFile.write(html, to: a.page)

            // 2. The voice-over, when the campaign is narrated: before the stills, so the sheet shows
            // the page at the voice's pace.
            var narration: NarrationInput?
            var voiceWarp: TimeWarp?
            var voiceProblem: String?
            if let asked = campaign.brief.voiceOver {
                if let provider = compute.voice {
                    do {
                        for track in day.asset?.voiceOver?.languages ?? [] { VoiceFinisher.removeFiles(of: track.language, assetPaths: a) }
                        let (selection, voice) = try await VoiceJob.speaker(asked, provider: provider, log: log)
                        let screen = await VoiceJob.textTimeline(a.page, readAccess: readAccess, log: log, emit: emit)
                        let lines = try await VoiceJob.script(day: day, html: html, onScreen: screen, project: project, paths: paths,
                                                              compute: compute, log: log, emit: emit)
                        let recorded = try await VoiceJob.record(lines, language: .english, selection: selection, existing: VoiceJob.existingLines(a, .english),
                                                                 assetPaths: a, paths: paths, voice: voice, compute: compute, log: log, emit: emit)
                        narration = NarrationInput(voice: selection, lines: recorded, scriptPath: paths.relative(a.script(.english)))
                        voiceWarp = VoiceJob.voiceWarp(recorded, duration: Double(duration), grid: nil, log: log)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        voiceProblem = "Voice-over skipped: \(error)"
                    }
                } else {
                    voiceProblem = "Voice-over skipped: no voice is on this Mac. Download one in Settings › Voice, then add the voice from this day."
                }
                if let voiceProblem { log.line(voiceProblem); emit(.problem(voiceProblem)) }
            }

            var input = FinishInput(paths: paths, assetPaths: a, readAccess: readAccess, day: day, html: html, notes: notes(page),
                                    altText: page.a11y.alt_text, descriptions: descriptions(page),
                                    scale: compute.settings.supersample ? 2 : 1, bitrate: compute.settings.bitrateMbps * 1_000_000, runID: log.id)
            input.renderer = compute.settings.renderer
            input.kit = kit
            input.narration = narration
            input.warp = voiceWarp
            input.placement = voiceWarp

            // 3. The stills and the sheet drawn from them.
            emit(.step("Stills"))
            log.step("Stills", day: dayIndex)
            var stills = try await AssetFinisher.stills(input)
            try ContactSheet.make(stills: stills, paths: paths, title: day.stem, duration: duration, to: a.sheet)
            emit(.sheet(dayIndex))

            // 4. The eyes on the sheet; the writer fixes what they find, once.
            var reviewed = false
            var reviewIssues: [String] = []
            if let eyes = compute.reviewer, let sheet = ImageFiles.jpegData(a.sheet, maxEdge: 2_152, quality: 0.9) {
                emit(.step("Reviewing the sheet"))
                log.step("Reviewing the sheet with \(eyes.info.title)", day: dayIndex)
                let look = ModelRequest(system: compute.prompts.system, turns: compute.prompts.review(day: day, html: page.html, sheet: sheet),
                                        format: Schemas.reviewFormat, maxTokens: 3_000, temperature: 0.3, label: "review")
                do {
                    let (review, _) = try await ModelCall.structured(ReviewResponse.self, model: eyes, request: look, log: log, emit: emit)
                    reviewed = true
                    reviewIssues = review.issues
                    if review.ok || review.issues.isEmpty {
                        log.line("review: ok")
                    } else {
                        log.line("review: \(review.issues.joined(separator: " | "))")
                        emit(.step("Fixing what the sheet shows"))
                        request.turns = compute.prompts.reviewFix(previous: request.turns, answer: answer.text, issues: review.issues)
                        request.thinking = .off
                        request.maxTokens = Self.pageTokens(duration)
                        let (revised, _) = try await ModelCall.structured(PageResponse.self, model: writer, request: request, log: log, emit: emit)
                        let revisedHTML = PageVerifier.rewriteKitPaths(revised.html, pageFolder: a.folder, kitFolder: kit)
                        let revisedProblems = try await check(revisedHTML, at: a, readAccess: readAccess, duration: duration)
                        if revisedProblems.isEmpty {
                            if narration != nil, PageVerifier.scenes(revisedHTML) != PageVerifier.scenes(html) {
                                log.line("the fix moved window.SCENES; the voice-over keeps the first page's timing")
                            }
                            html = revisedHTML
                            page = revised
                            try AtomicFile.write(html, to: a.page)
                            input.html = html
                            input.notes = notes(page)
                            input.altText = page.a11y.alt_text
                            input.descriptions = descriptions(page)
                            stills = try await AssetFinisher.stills(input)
                            try ContactSheet.make(stills: stills, paths: paths, title: day.stem, duration: duration, to: a.sheet)
                            emit(.sheet(dayIndex))
                        } else {
                            try AtomicFile.write(html, to: a.page)
                            log.line("the fix was kept out (\(revisedProblems.joined(separator: " | "))): the first page stands")
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    log.line("review skipped: \(error)")
                }
            }

            // 5. The day, sheeted.
            var asset = day.asset ?? Asset(folder: paths.relative(a.folder), duration: duration, pagePath: paths.relative(a.page))
            asset.duration = duration
            asset.pagePath = paths.relative(a.page)
            asset.renders = []; asset.originals = []; asset.originalA11y = nil; asset.originalWarp = nil
            if asset.music != nil { log.line("the song this day was cut to is dropped: the page changed"); asset.music = nil }
            asset.stills = stills
            asset.sheetPath = paths.relative(a.sheet)
            asset.notes = input.notes
            // Stored in video time, as a rendered asset's are (`pageDescriptions` maps them back).
            let cues = input.descriptions.map { cue in
                Cue(start: voiceWarp?.realTime(forPage: cue.start) ?? cue.start, end: voiceWarp?.realTime(forPage: cue.end) ?? cue.end,
                    text: cue.text, kind: .description)
            }
            asset.a11y = A11y(altText: input.altText, descriptions: cues)
            asset.warp = voiceWarp
            asset.voiceOver = narration.map { n in
                VoiceOver(selection: n.voice, english: VoiceTrack(language: .english, scriptPath: n.scriptPath, lines: n.lines,
                                                                  characters: n.lines.reduce(0) { $0 + $1.characters }))
            }
            asset.reviewed = reviewed
            asset.builtAt = Date()
            asset.buildRunID = log.id
            let written = asset
            let dayProblem = voiceProblem
            try await CampaignLedger.shared.updateDay(paths, index: dayIndex) { d in
                d.asset = written
                d.problem = dayProblem
                d.redoNote = note
                d.approvedAt = nil
                if d.status != .posted && d.status != .skipped { d.status = .sheeted }
            }
            if !reviewIssues.isEmpty { log.line("the eyes saw: \(reviewIssues.joined(separator: " | "))") }
            emit(.dayDone(dayIndex))
            log.finish(.succeeded)
        } catch is CancellationError {
            log.finish(.cancelled); throw CancellationError()
        } catch RenderError.cancelled {
            log.finish(.cancelled); throw CancellationError()
        } catch {
            let message = "\(error)"
            _ = try? await CampaignLedger.shared.updateDay(paths, index: dayIndex) { $0.problem = message }
            emit(.problem(message))
            log.finish(.failed(message))
            throw error
        }
    }

    /// What a page and its notes take: a 15 s page is about 6,000 tokens, a 30 s one about 9,000;
    /// half again for room, no more (a page past this is a page that has lost its way).
    static func pageTokens(_ duration: Int) -> Int { duration > 15 ? 14_000 : 10_000 }

    static func notes(_ page: PageResponse) -> AssetNotes {
        AssetNotes(summary: page.notes.summary, illustrative: page.notes.illustrative, softened: page.notes.softened, sources: page.notes.sources)
    }

    /// The descriptions in page time.
    static func descriptions(_ page: PageResponse) -> [Cue] {
        page.a11y.descriptions.map { Cue(start: $0.at, end: $0.until, text: $0.text, kind: .description) }
    }

    /// The contract statically, then in the renderer: does it boot, are the faces there, does
    /// seeking across the timeline throw.
    static func check(_ html: String, at a: AssetPaths, readAccess: URL, duration: Int) async throws -> [String] {
        var problems = PageVerifier.problems(html, duration: duration) + ScriptCheck.problems(html)
        guard problems.isEmpty else { return problems }
        try AtomicFile.write(html, to: a.page)
        do {
            let info = try await PageRenderer.probe(page: a.page, readAccess: readAccess)
            if abs(info.dur - Double(duration)) > 0.01 { problems.append("window.DUR is \(info.dur), not \(duration).") }
            problems += info.errors.prefix(5).map { "The page threw: \($0)" }
            if !info.missingFonts.isEmpty { problems.append("Fonts did not load: \(info.missingFonts.joined(separator: ", ")). Link kit.css as the template does.") }
            if info.scenes.isEmpty { problems.append("window.SCENES is empty.") }
        } catch let error as RenderError {
            problems.append("The page did not boot in the renderer: \(error)")
        }
        return problems
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
