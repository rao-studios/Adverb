//
//  VoiceJob.swift
//  AdverbAgents
//
//  WHAT: A day's voice-over. English: Claude writes the lines for the built page (or the lines it
//        has are kept), ElevenLabs speaks them, and they are mixed onto both renders with the
//        captions and transcript made from them. Languages: the confirmed English translated by
//        Claude, spoken in the same voice, and remuxed from the English renders onto each
//        language's own videos. The build's voice step uses the same script and record helpers.
//  PIN:  Lines too long for their window are recorded faster first (≤ 1.15×), then shortened by
//        Claude once; what is still long is kept and logged (it runs into the next scene).
//

import AdverbCore
import AdverbRender
import Foundation

public enum VoiceError: Error, Equatable, CustomStringConvertible {
    case notBuilt
    case noEnglish
    case notConfirmed

    public var description: String {
        switch self {
        case .notBuilt: "Build the day before giving it a voice."
        case .noEnglish: "The day has no English voice-over yet."
        case .notConfirmed: "Confirm the English voice-over first."
        }
    }
}

/// Says a step once, then only its progress.
final class StepTeller: @unchecked Sendable {
    private let lock = NSLock()
    private var last: String?
    let emit: @Sendable (GenerationEvent) -> Void
    init(_ emit: @escaping @Sendable (GenerationEvent) -> Void) { self.emit = emit }
    func callAsFunction(_ step: String, _ p: Double) {
        let isNew = lock.withLock { () -> Bool in defer { last = step }; return last != step }
        if isNew { emit(.step(step)) }
        emit(.progress(p))
    }
}

public enum VoiceJob {
    public static func run(projectSlug: String, campaignID: UUID, dayIndex: Int, task: VoiceTask, compute: AdverbCompute,
                           emit: @escaping @Sendable (GenerationEvent) -> Void) async throws {
        let project = try compute.project(projectSlug)
        let paths = compute.paths(project, campaignID)
        let kind: RunKind
        switch task {
        case .english: kind = .voice(day: dayIndex)
        case .languages(let languages): kind = .languages(day: dayIndex, languages)
        }
        let log = RunLog(paths: paths, campaignID: campaignID, kind: kind, model: compute.settings.model)
        do {
            let campaign = try await CampaignLedger.shared.read(paths)
            guard let day = campaign.day(dayIndex) else { throw CampaignError.noDay(dayIndex) }
            guard let asset = day.asset, !asset.renders.isEmpty else { throw VoiceError.notBuilt }
            guard let client = compute.voice else { throw ElevenLabsError.noKey }
            switch task {
            case .english(let selection, let rescript):
                try await english(selection, rescript: rescript, day: day, asset: asset, project: project, paths: paths,
                                  client: client, compute: compute, log: log, emit: emit)
            case .languages(let languages):
                try await languagesRun(languages, day: day, asset: asset, project: project, paths: paths,
                                       client: client, compute: compute, log: log, emit: emit)
            }
            if let v = log.voice { emit(.voiceUsage(v)) }
            log.finish(.succeeded)
        } catch is CancellationError {
            log.finish(.cancelled); throw CancellationError()
        } catch RenderError.cancelled {
            log.finish(.cancelled); throw CancellationError()
        } catch {
            let message = "\(error)"
            _ = try? await CampaignLedger.shared.updateDay(paths, index: dayIndex) { $0.problem = "Voice-over: \(message)" }
            emit(.problem(message))
            log.finish(.failed(message))
            throw error
        }
    }

    // MARK: - English

    static func english(_ selection: VoiceSelection, rescript: Bool, day: CampaignDay, asset: Asset, project: Project, paths: CampaignPaths,
                        client: ElevenLabsClient, compute: AdverbCompute, log: RunLog, emit: @escaping @Sendable (GenerationEvent) -> Void) async throws {
        let a = paths.asset(day.stem)
        log.line("\(day.date) · \(day.topic.title) · \(selection.voiceName) (\(selection.modelID))")
        var lines = asset.voiceOver?.english.lines ?? []
        if rescript || lines.isEmpty {
            // The lines are timed to the page the asset was built from (before any re-cut).
            let original = a.original.appendingPathComponent("page.html")
            let html = (try? String(contentsOf: FileManager.default.fileExists(atPath: original.path) ? original : a.page, encoding: .utf8)) ?? ""
            lines = try await script(day: day, html: html, project: project, paths: paths, compute: compute, log: log, emit: emit)
        }
        lines = try await record(lines, language: .english, selection: selection, existing: existingLines(a, .english), assetPaths: a,
                                 paths: paths, client: client, compute: compute, log: log, emit: emit)
        let tell = StepTeller(emit)
        let input = VoiceApplyInput(paths: paths, assetPaths: a, day: day, music: asset.music, warp: asset.warp, progress: { tell($0, $1) })
        let updated = try await VoiceFinisher.applyEnglish(asset, selection: selection, lines: lines, scriptPath: paths.relative(a.script(.english)), input: input)
        for render in updated.renders { log.line("\(render.orientation.rawValue): \(render.report?.line ?? render.path)") }
        for check in updated.a11y.checks { log.line("a11y \(check.level.rawValue): \(check.message)") }
        try await CampaignLedger.shared.updateDay(paths, index: day.index) { d in d.asset = updated; d.problem = nil }
        emit(.dayDone(day.index))
    }

    // MARK: - Languages

    static func languagesRun(_ languages: [Language], day: CampaignDay, asset: Asset, project: Project, paths: CampaignPaths,
                             client: ElevenLabsClient, compute: AdverbCompute, log: RunLog, emit: @escaping @Sendable (GenerationEvent) -> Void) async throws {
        guard var vo = asset.voiceOver, !vo.english.lines.isEmpty, vo.english.lines.allSatisfy(\.isRecorded) else { throw VoiceError.noEnglish }
        guard vo.isConfirmed else { throw VoiceError.notConfirmed }
        let a = paths.asset(day.stem)
        var current = asset
        let englishText = vo.english.lines.map(\.text)
        let tell = StepTeller(emit)
        for language in languages.sorted() where language != .english {
            try Task.checkCancellation()
            log.line("\(language.title) · \(vo.voiceName)")
            var track = vo.track(language) ?? VoiceTrack(language: language, scriptPath: paths.relative(a.script(language)), lines: [])
            if track.stale || track.lines.count != vo.english.lines.count || track.translatedFrom != englishText {
                track.lines = try await translate(vo.english.lines, into: language, day: day, project: project, paths: paths,
                                                  compute: compute, log: log, emit: emit)
                track.translatedFrom = englishText
            }
            track.lines = try await record(track.lines, language: language, selection: vo.selection, existing: existingLines(a, language) + track.lines,
                                           assetPaths: a, paths: paths, client: client, compute: compute, log: log, emit: emit)
            track.stale = false
            track.scriptPath = paths.relative(a.script(language))
            vo.upsert(track)
            current.voiceOver = vo
            let input = VoiceApplyInput(paths: paths, assetPaths: a, day: day, music: current.music, warp: current.warp, progress: { tell($0, $1) })
            current = try await VoiceFinisher.deriveLanguages(current, only: [language], input: input)
            vo = current.voiceOver ?? vo
            for render in vo.track(language)?.renders ?? [] { log.line("\(language.code) \(render.orientation.rawValue): \(render.report?.line ?? render.path)") }
            let written = vo
            try await CampaignLedger.shared.updateDay(paths, index: day.index) { d in d.asset?.voiceOver = written; d.problem = nil }
            emit(.dayDone(day.index))
        }
    }

    // MARK: - Shared with the build

    /// Claude's lines for the page, held to the contract (one round of fixes).
    public static func script(day: CampaignDay, html: String, project: Project, paths: CampaignPaths, compute: AdverbCompute, log: RunLog,
                              emit: @escaping @Sendable (GenerationEvent) -> Void) async throws -> [NarrationLine] {
        emit(.step("Scripting the voice-over"))
        log.step("Scripting the voice-over", day: day.index)
        let digest = try compute.digest(project, paths: paths)
        let duration = Double(day.topic.duration)
        let messages = compute.prompts.narrate(digest: digest.text, day: day, scenes: PageVerifier.scenes(html), duration: day.topic.duration, project: project)
        var request = ClaudeRequest(system: compute.prompts.system, messages: messages, schema: Schemas.narration, maxTokens: 16_000)
        var (answer, message) = try await ClaudeCall.structured(NarrationResponse.self, client: compute.client, request: request, log: log, emit: emit)
        var lines = NarrationCaptions.lines(from: answer)
        let problems = NarrationCaptions.problems(lines, duration: duration)
        if !problems.isEmpty {
            emit(.step("Fixing the voice-over"))
            log.step("Fixing: \(problems.joined(separator: " | "))", day: day.index)
            request.messages = compute.prompts.narrateFix(previous: messages, answer: message.text, problems: problems)
            (answer, message) = try await ClaudeCall.structured(NarrationResponse.self, client: compute.client, request: request, log: log, emit: emit)
            lines = NarrationCaptions.lines(from: answer)
            let structural = NarrationCaptions.problems(lines, duration: duration, pacing: false)
            guard structural.isEmpty else { throw ClaudeError.invalid("The voice-over still breaks its contract: " + structural.joined(separator: " ")) }
            let pacing = NarrationCaptions.problems(lines, duration: duration)
            if !pacing.isEmpty { log.line("kept with pacing notes: \(pacing.joined(separator: " | "))") }
        }
        for line in lines { log.line(String(format: "%5.2f–%5.2f  %@", line.at, line.until, line.text)) }
        return lines
    }

    /// The lines spoken; lines too long even at 1.15× shortened by Claude once and spoken again.
    /// Writes voice/<code>/script.json.
    public static func record(_ lines: [NarrationLine], language: Language, selection: VoiceSelection, existing: [NarrationLine],
                              assetPaths a: AssetPaths, paths: CampaignPaths, client: ElevenLabsClient, compute: AdverbCompute,
                              log: RunLog, emit: @escaping @Sendable (GenerationEvent) -> Void) async throws -> [NarrationLine] {
        let step = language == .english ? "Recording the voice-over" : "Recording \(language.title)"
        emit(.step(step))
        log.step(step)
        var result = try await VoiceSynth.synthesize(lines, language: language, selection: selection, existing: existing, assetPaths: a,
                                                     paths: paths, client: client, log: log, emit: emit)
        if !result.long.isEmpty {
            let label = "Shortening \(result.long.count) \(result.long.count == 1 ? "line" : "lines")"
            emit(.step(label))
            log.step(label)
            let request = ClaudeRequest(system: compute.prompts.system,
                                        messages: compute.prompts.narrateShorten(lines: result.lines, long: result.long, language: language),
                                        schema: Schemas.narration, maxTokens: 16_000)
            let (answer, _) = try await ClaudeCall.structured(NarrationResponse.self, client: compute.client, request: request, log: log, emit: emit)
            let shorter = answer.lines.sorted { $0.at < $1.at }
            if shorter.count == result.lines.count {
                let long = Set(result.long.map(\.index))
                var revised = result.lines
                for i in revised.indices where long.contains(revised[i].index) {
                    let text = shorter[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, text != revised[i].text else { continue }
                    revised[i] = NarrationLine(index: revised[i].index, text: text, at: revised[i].at, until: revised[i].until,
                                               characters: text.count, speed: revised[i].speed, shortened: true)
                    log.line("line \(revised[i].index) shortened: \(text)")
                }
                emit(.step(step))
                result = try await VoiceSynth.synthesize(revised, language: language, selection: selection, existing: result.lines,
                                                         assetPaths: a, paths: paths, client: client, log: log, emit: emit)
            } else {
                log.line("the shortened script had \(shorter.count) lines, not \(result.lines.count); kept the first")
            }
            for l in result.long { log.line(String(format: "line %d runs %.2f s for a %.2f s window; it runs into the next", l.index, l.spoken, l.window)) }
        }
        let script = NarrationScript(language: language, voiceID: selection.voiceID, modelID: selection.modelID, lines: result.lines)
        try JSONCoding.write(script, to: a.script(language))
        return result.lines
    }

    /// The English lines in `language`, in the English windows (one round of fixes if the count is off).
    public static func translate(_ english: [NarrationLine], into language: Language, day: CampaignDay, project: Project, paths: CampaignPaths,
                                 compute: AdverbCompute, log: RunLog, emit: @escaping @Sendable (GenerationEvent) -> Void) async throws -> [NarrationLine] {
        let step = "Translating into \(language.title)"
        emit(.step(step))
        log.step(step, day: day.index)
        let digest = try compute.digest(project, paths: paths)
        let messages = compute.prompts.translate(digest: digest.text, lines: english, language: language, day: day, project: project)
        var request = ClaudeRequest(system: compute.prompts.system, messages: messages, schema: Schemas.narration, maxTokens: 16_000)
        var (answer, message) = try await ClaudeCall.structured(NarrationResponse.self, client: compute.client, request: request, log: log, emit: emit)
        var lines = NarrationCaptions.translated(answer, from: english)
        if lines == nil || lines!.contains(where: { $0.text.isEmpty }) {
            request.messages = compute.prompts.narrateFix(previous: messages, answer: message.text,
                                                          problems: ["Return exactly \(english.count) lines, one per English line, none empty, same at and until."])
            (answer, message) = try await ClaudeCall.structured(NarrationResponse.self, client: compute.client, request: request, log: log, emit: emit)
            lines = NarrationCaptions.translated(answer, from: english)
        }
        guard let lines, !lines.contains(where: { $0.text.isEmpty }) else {
            throw ClaudeError.invalid("The \(language.title) translation did not keep the English lines.")
        }
        for line in lines { log.line(String(format: "%5.2f  %@", line.at, line.text)) }
        return lines
    }

    /// What voice/<code>/script.json holds, so its clips can be used again.
    static func existingLines(_ a: AssetPaths, _ language: Language) -> [NarrationLine] {
        (try? JSONCoding.read(NarrationScript.self, from: a.script(language)))?.lines ?? []
    }
}
