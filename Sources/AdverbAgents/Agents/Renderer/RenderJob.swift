//
//  RenderJob.swift
//  AdverbAgents
//
//  WHAT: Renders a day from its sheet: the page as it was approved (and its voice-over, already
//        spoken and timed), both orientations to MP4 with the voice mixed in, the captions, the
//        descriptions, the transcript, the checks, and the contact sheet drawn again from the
//        videos. No model is asked anything: what was approved is what is rendered.
//  PIN:  Renders take turns across days (RenderGate); the stills the sheet was drawn from are
//        reused when they are all still on disk.
//

import AdverbCore
import AdverbRender
import Foundation

public enum RenderJob {
    public static func run(projectSlug: String, campaignID: UUID, dayIndex: Int, compute: AdverbCompute,
                           emit: @escaping @Sendable (GenerationEvent) -> Void) async throws {
        let project = try compute.project(projectSlug)
        let paths = compute.paths(project, campaignID)
        let log = RunLog(paths: paths, campaignID: campaignID, kind: .render(day: dayIndex), model: "")
        do {
            let campaign = try await CampaignLedger.shared.read(paths)
            guard let day = campaign.day(dayIndex) else { throw CampaignError.noDay(dayIndex) }
            guard let asset = day.asset, FileManager.default.fileExists(atPath: paths.url(asset.pagePath).path) else { throw RenderJobError.noSheet }
            let a = paths.asset(day.stem)
            let html = try String(contentsOf: a.page, encoding: .utf8)
            let kit = compute.kitFolder(project)
            let readAccess = compute.workspace.projectFolder(project.slug)
            log.line("\(day.date) · \(day.topic.title) · \(day.topic.duration) s · \(day.stem)")

            var input = FinishInput(paths: paths, assetPaths: a, readAccess: readAccess, day: day, html: html, notes: asset.notes,
                                    altText: asset.a11y.altText, descriptions: asset.pageDescriptions,
                                    scale: compute.settings.supersample ? 2 : 1, bitrate: compute.settings.bitrateMbps * 1_000_000,
                                    previous: asset, runID: log.id)
            input.renderer = compute.settings.renderer
            input.kit = kit
            input.warp = asset.warp
            input.placement = asset.warp
            if let vo = asset.voiceOver, !vo.english.lines.isEmpty, vo.english.lines.allSatisfy(\.isRecorded) {
                input.narration = NarrationInput(voice: vo.selection, lines: vo.english.lines, scriptPath: vo.english.scriptPath)
            }
            var stills = asset.stills
            if stills.isEmpty || stills.contains(where: { !FileManager.default.fileExists(atPath: paths.url($0.path).path) }) {
                emit(.step("Stills"))
                stills = try await AssetFinisher.stills(input)
            }

            emit(.step("Waiting to render"))
            log.step("Rendering", day: dayIndex)
            let finalInput = input
            let finalStills = stills
            var rendered = try await RenderGate.shared.run {
                try await AssetFinisher.finish(finalInput, stills: finalStills, progress: { step, p in
                    emit(.step(step.rawValue)); emit(.progress(p))
                })
            }
            rendered.reviewed = asset.reviewed
            for render in rendered.renders { log.line("\(render.orientation.rawValue): \(render.report?.line ?? render.path) \(render.report?.warnings.joined(separator: "; ") ?? "")") }
            for check in rendered.a11y.checks { log.line("a11y \(check.level.rawValue): \(check.message)") }
            let built = rendered
            try await CampaignLedger.shared.updateDay(paths, index: dayIndex) { d in
                d.asset = built
                d.problem = nil
                if d.status != .posted && d.status != .skipped { d.status = .rendered }
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
}

public enum RenderJobError: Error, Equatable, CustomStringConvertible {
    case noSheet
    public var description: String { "Write the day's sheet before rendering it." }
}
