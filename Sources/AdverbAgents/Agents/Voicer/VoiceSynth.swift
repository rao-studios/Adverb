//
//  VoiceSynth.swift
//  AdverbAgents
//
//  WHAT: A script's lines spoken by ElevenLabs, one request per line, each clip written to
//        voice/<code>/line-NN.mp3 with when its speech starts and ends. The voice carries on from
//        line to line (the text either side, the last three request ids). A line that runs past
//        its window is asked again faster, up to 1.15×; what is still long is handed back.
//  PIN:  A line whose text, voice, model, language and speed match a clip already on disk is not
//        asked for again: a remix, a re-cut or a superseded run never spends characters twice.
//

import AdverbCore
import AdverbRender
import Foundation

enum VoiceSynth {
    struct Result {
        var lines: [NarrationLine]
        var usage: VoiceUsage
        /// Lines still too long for their windows: (index, spoken seconds, allowed seconds).
        var long: [(index: Int, spoken: Double, window: Double)]
    }

    static func synthesize(_ lines: [NarrationLine], language: Language, selection: VoiceSelection, existing: [NarrationLine],
                           assetPaths a: AssetPaths, paths: CampaignPaths, client: ElevenLabsClient, log: RunLog,
                           emit: @escaping @Sendable (GenerationEvent) -> Void) async throws -> Result {
        try FileManager.default.createDirectory(at: a.voice(language), withIntermediateDirectories: true)
        var out = lines
        var usage = VoiceUsage(modelID: selection.modelID)
        // What the run had spent before this call: the events carry the run's total.
        let before = log.voice ?? VoiceUsage(modelID: selection.modelID)
        var long: [(Int, Double, Double)] = []
        var requestIDs: [String] = []
        let cached = Dictionary(existing.compactMap { l in l.cacheKey.map { ($0, l) } }, uniquingKeysWith: { a, _ in a })
        for i in out.indices {
            try Task.checkCancellation()
            emit(.progress(Double(i) / Double(max(1, out.count))))
            let line = out[i]
            let allowed = max(0.5, line.window - NarrationPacing.fitSlack)
            var speed = line.shortened ? max(line.speed, selection.settings.speed) : selection.settings.speed
            // A clip made before for these exact words in this voice (at this speed, or the faster
            // take a long line was given) is used as it is.
            let hit = cached[cacheKey(text: line.text, selection: selection, language: language, speed: speed)]
                ?? existing.first { $0.index == line.index && $0.text == line.text && $0.cacheKey != nil
                    && $0.cacheKey == cacheKey(text: line.text, selection: selection, language: language, speed: $0.speed) }
            if let hit, let clip = hit.clipPath, FileManager.default.fileExists(atPath: paths.url(clip).path) {
                var reused = hit
                reused.index = line.index; reused.at = line.at; reused.until = line.until; reused.shortened = line.shortened
                out[i] = reused
                if let id = hit.requestID { requestIDs.append(id) }
                continue
            }
            var recorded = try await speak(line, index: i, in: out, language: language, selection: selection, speed: speed,
                                           previousIDs: requestIDs, a: a, paths: paths, client: client, usage: &usage)
            emit(.voiceUsage(before + usage))
            // Too long: once more, faster.
            if let spoken = recorded.spokenEnd, spoken > allowed {
                let faster = fitSpeed(spoken: spoken, allowed: allowed, speed: speed)
                if faster > speed + 0.005 {
                    log.line(String(format: "line %d ran %.2f s for %.2f s; again at %.2f×", line.index, spoken, allowed, faster))
                    speed = faster
                    recorded = try await speak(line, index: i, in: out, language: language, selection: selection, speed: speed,
                                               previousIDs: requestIDs, a: a, paths: paths, client: client, usage: &usage)
                    emit(.voiceUsage(before + usage))
                }
                if let still = recorded.spokenEnd, still > allowed { long.append((line.index, still, allowed)) }
            }
            out[i] = recorded
            if let id = recorded.requestID { requestIDs.append(id) }
        }
        emit(.progress(1))
        log.add(voice: usage)
        return Result(lines: out, usage: usage, long: long)
    }

    static func speak(_ line: NarrationLine, index i: Int, in lines: [NarrationLine], language: Language, selection: VoiceSelection,
                      speed: Double, previousIDs: [String], a: AssetPaths, paths: CampaignPaths, client: ElevenLabsClient,
                      usage: inout VoiceUsage) async throws -> NarrationLine {
        var settings = selection.settings
        settings.speed = speed
        let request = TTSRequest(voiceID: selection.voiceID, text: line.text, modelID: selection.modelID, languageCode: language.code,
                                 settings: settings, previousText: i > 0 ? lines[i - 1].text : nil,
                                 nextText: i + 1 < lines.count ? lines[i + 1].text : nil,
                                 previousRequestIDs: Array(previousIDs.suffix(3)))
        let result = try await client.speak(request)
        usage = usage + VoiceUsage(characters: result.characters, requests: 1, modelID: selection.modelID)
        let file = a.clip(language, line.index)
        try AtomicFile.write(result.audio, to: file)
        let seconds = await AudioSampleSource.length(file)
        var out = line
        let span = result.alignment?.spokenSpan
        out.spokenStart = span?.start ?? 0
        out.spokenEnd = span?.end ?? seconds ?? line.window
        out.words = result.alignment?.words ?? []
        out.clipPath = paths.relative(file)
        out.clipSeconds = seconds
        out.characters = result.characters
        out.requestID = result.requestID
        out.speed = speed
        out.cacheKey = cacheKey(text: line.text, selection: selection, language: language, speed: speed)
        return out
    }

    /// The speed that brings `spoken` seconds (at `speed`) inside `allowed`, with 2 % to spare;
    /// never slower than now, never faster than 1.15×.
    static func fitSpeed(spoken: Double, allowed: Double, speed: Double) -> Double {
        guard allowed > 0, spoken > allowed else { return speed }
        return min(NarrationPacing.maxSpeed, max(speed, (speed * spoken / allowed * 1.02 * 100).rounded(.up) / 100))
    }

    static func cacheKey(text: String, selection: VoiceSelection, language: Language, speed: Double) -> String {
        let s = selection.settings
        return ContextDigestBuilder.sha([text, selection.voiceID, selection.modelID, language.code, String(format: "%.2f", speed),
                                         String(format: "%.2f/%.2f/%.2f/%d", s.stability, s.similarityBoost, s.style, s.useSpeakerBoost ? 1 : 0)]
            .joined(separator: "\u{1F}"))
    }
}
