//
//  BuildJob.swift
//  AdverbAgents
//
//  WHAT: Builds one day's asset: the page (Claude, with the skill, the frozen digest and the
//        day's plan), checked statically and in the renderer (one round of fixes), stills,
//        Claude's review of the stills (one round), then both renders, captions, descriptions,
//        transcript, checks and the contact sheet; the asset written to the day. A narrated
//        campaign's day also gets its voice-over (Claude's lines, ElevenLabs' voice) before the
//        stills, mixed in as it renders.
//  PIN:  A day that fails says why on the day itself (`problem`), and the run fails with it; the
//        other days are untouched. A voice-over that fails does not fail the day: it finishes
//        silent, says why, and the voice can be added from the day without a rebuild.
//

import AdverbCore
import AdverbRender
import Foundation

public enum BuildJob {
    public static func run(projectSlug: String, campaignID: UUID, dayIndex: Int, compute: AdverbCompute,
                           emit: @escaping @Sendable (GenerationEvent) -> Void) async throws {
        var project = try compute.project(projectSlug)
        let paths = compute.paths(project, campaignID)
        let log = RunLog(paths: paths, campaignID: campaignID, kind: .build(days: [dayIndex]), model: compute.settings.model)
        do {
            let campaign = try await CampaignLedger.shared.read(paths)
            guard let day = campaign.day(dayIndex) else { throw CampaignError.noDay(dayIndex) }
            project = try ProjectStore(workspace: compute.workspace).ensureKit(project)
            let kit = compute.kitFolder(project)
            let a = paths.asset(day.stem)
            try FileManager.default.createDirectory(at: a.folder, withIntermediateDirectories: true)
            let readAccess = compute.workspace.projectFolder(project.slug)
            let digest = try compute.digest(project, paths: paths)
            log.line("\(day.date) · \(day.topic.title) · \(day.topic.duration) s · \(day.stem)")

            // 1. The page.
            emit(.step("Writing the page"))
            log.step("Writing the page", day: dayIndex)
            let messages = compute.prompts.build(digest: digest.text, day: day, campaign: campaign, project: project)
            var request = ClaudeRequest(system: compute.prompts.system, messages: messages, schema: Schemas.page, maxTokens: 64_000)
            var (page, message) = try await ClaudeCall.structured(PageResponse.self, client: compute.client, request: request, log: log, emit: emit)
            var html = PageVerifier.rewriteKitPaths(page.html, pageFolder: a.folder, kitFolder: kit)
            var problems = try await check(html, at: a, readAccess: readAccess, duration: day.topic.duration)
            if !problems.isEmpty {
                emit(.step("Fixing the page"))
                log.step("Fixing: \(problems.joined(separator: " | "))", day: dayIndex)
                request.messages = compute.prompts.buildFix(previous: messages, answer: message.text, problems: problems)
                (page, message) = try await ClaudeCall.structured(PageResponse.self, client: compute.client, request: request, log: log, emit: emit)
                html = PageVerifier.rewriteKitPaths(page.html, pageFolder: a.folder, kitFolder: kit)
                problems = try await check(html, at: a, readAccess: readAccess, duration: day.topic.duration)
                guard problems.isEmpty else { throw ClaudeError.invalid("The page still breaks the contract: " + problems.joined(separator: " ")) }
            }
            try AtomicFile.write(html, to: a.page)

            // 1b. The voice-over, when the campaign is narrated.
            var narration: NarrationInput?
            var voiceWarp: TimeWarp?
            var voiceProblem: String?
            if let selection = campaign.brief.voiceOver {
                if let client = compute.voice {
                    do {
                        // A rebuild replaces the day's voice-over: the old languages' files go.
                        for track in day.asset?.voiceOver?.languages ?? [] { VoiceFinisher.removeFiles(of: track.language, assetPaths: a) }
                        let screen = await VoiceJob.textTimeline(a.page, readAccess: readAccess, log: log, emit: emit)
                        let lines = try await VoiceJob.script(day: day, html: html, onScreen: screen, project: project, paths: paths, compute: compute, log: log, emit: emit)
                        let recorded = try await VoiceJob.record(lines, language: .english, selection: selection, existing: VoiceJob.existingLines(a, .english),
                                                                 assetPaths: a, paths: paths, client: client, compute: compute, log: log, emit: emit)
                        narration = NarrationInput(voice: selection, lines: recorded, scriptPath: paths.relative(a.script(.english)))
                        voiceWarp = VoiceJob.voiceWarp(recorded, duration: Double(day.topic.duration), grid: nil, log: log)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        voiceProblem = "Voice-over skipped: \(error)"
                    }
                } else {
                    voiceProblem = "Voice-over skipped: there is no ElevenLabs key. Add one in Settings › Voice, then add the voice from this day."
                }
                if let voiceProblem { log.line(voiceProblem); emit(.problem(voiceProblem)) }
            }

            var input = FinishInput(paths: paths, assetPaths: a, readAccess: readAccess, day: day, html: html,
                                    notes: AssetNotes(summary: page.notes.summary, illustrative: page.notes.illustrative,
                                                      softened: page.notes.softened, sources: page.notes.sources),
                                    altText: page.a11y.alt_text,
                                    descriptions: page.a11y.descriptions.map { Cue(start: $0.at, end: $0.until, text: $0.text, kind: .description) },
                                    scale: compute.settings.supersample ? 2 : 1, bitrate: compute.settings.bitrateMbps * 1_000_000,
                                    previous: nil, runID: log.id)
            input.renderer = compute.settings.renderer
            input.kit = kit
            input.narration = narration
            // The page plays at the voice's pace: each line's text arrives on its first word.
            input.warp = voiceWarp
            input.placement = voiceWarp

            // 2. Stills, and Claude's look at them.
            emit(.step("Stills"))
            log.step("Stills", day: dayIndex)
            var stills = try await AssetFinisher.stills(input)
            var reviewed = false
            if compute.settings.reviewPass {
                emit(.step("Reviewing the stills"))
                log.step("Reviewing the stills", day: dayIndex)
                let images = stills.compactMap { still -> (label: String, jpeg: Data)? in
                    ImageFiles.jpegData(paths.url(still.path)).map { (String(format: "%@ at %.1f s", still.orientation.title, still.time), $0) }
                }
                let reviewRequest = ClaudeRequest(system: compute.prompts.system,
                                                  messages: compute.prompts.review(day: day, html: page.html, stills: images),
                                                  schema: Schemas.review, maxTokens: 64_000)
                let (review, _) = try await ClaudeCall.structured(ReviewResponse.self, client: compute.client, request: reviewRequest, log: log, emit: emit)
                reviewed = true
                if review.ok || review.html.isEmpty {
                    log.line("review: ok")
                } else {
                    log.line("review: \(review.issues.joined(separator: " | "))")
                    let revised = PageVerifier.rewriteKitPaths(review.html, pageFolder: a.folder, kitFolder: kit)
                    let revisedProblems = try await check(revised, at: a, readAccess: readAccess, duration: day.topic.duration)
                    if revisedProblems.isEmpty {
                        if narration != nil, PageVerifier.scenes(revised) != PageVerifier.scenes(html) {
                            log.line("the review moved window.SCENES; the voice-over keeps the first page's timing")
                        }
                        html = revised
                        try AtomicFile.write(html, to: a.page)
                        input.html = html
                        stills = try await AssetFinisher.stills(input)
                    } else {
                        // The review's page broke the contract: keep the first, which passed.
                        try AtomicFile.write(html, to: a.page)
                        log.line("review's revision kept out: \(revisedProblems.joined(separator: " | "))")
                    }
                }
            }

            // 3. Renders, captions, sheet: one render at a time across builders.
            emit(.step("Waiting to render"))
            let finalInput = input
            let finalStills = stills
            var asset = try await RenderGate.shared.run {
                try await AssetFinisher.finish(finalInput, stills: finalStills, progress: { step, p in
                    emit(.step(step.rawValue)); emit(.progress(p))
                })
            }
            asset.reviewed = reviewed
            for render in asset.renders { log.line("\(render.orientation.rawValue): \(render.report?.line ?? render.path) \(render.report?.warnings.joined(separator: "; ") ?? "")") }
            for check in asset.a11y.checks { log.line("a11y \(check.level.rawValue): \(check.message)") }

            let built = asset
            let dayProblem = voiceProblem
            try await CampaignLedger.shared.updateDay(paths, index: dayIndex) { d in
                d.asset = built
                d.problem = dayProblem
                if d.status == .planned { d.status = .rendered }
            }
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

    /// The contract statically, then in the renderer: does it boot, are the faces there, does
    /// seeking across the timeline throw.
    static func check(_ html: String, at a: AssetPaths, readAccess: URL, duration: Int) async throws -> [String] {
        var problems = PageVerifier.problems(html, duration: duration)
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
