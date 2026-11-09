//
//  VoiceSynth.swift
//  AdverbAgents
//
//  WHAT: A script's lines spoken by the voice on this Mac, one clip per line, each written to
//        voice/<code>/line-NN.wav with when its speech starts and ends and when each word is said.
//        A line that runs past its window is spoken again faster, up to 1.15×, when the voice can;
//        what is still long is handed back to be shortened.
//  PIN:  A line whose text, voice, pack, language and speed match a clip already on disk is not
//        spoken again: a remix, a re-cut or a superseded run never makes the same clip twice. The
//        voice is seeded, so a clip made again is the clip it was.
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
                           assetPaths a: AssetPaths, paths: CampaignPaths, voice: any SpeechSynthesizer, log: RunLog,
                           emit: @escaping @Sendable (GenerationEvent) -> Void) async throws -> Result {
        try FileManager.default.createDirectory(at: a.voice(language), withIntermediateDirectories: true)
        let pack = voice.pack
        var out = lines
        var usage = VoiceUsage(packID: pack.id)
        // What the run had spoken before this call: the events carry the run's total.
        let before = log.voice ?? VoiceUsage(packID: pack.id)
        var long: [(Int, Double, Double)] = []
        let cached = Dictionary(existing.compactMap { l in l.cacheKey.map { ($0, l) } }, uniquingKeysWith: { a, _ in a })
        for i in out.indices {
            try Task.checkCancellation()
            emit(.progress(Double(i) / Double(max(1, out.count))))
            let line = out[i]
            let allowed = max(0.5, line.window - NarrationPacing.fitSlack)
            var speed = line.shortened ? max(line.speed, selection.speed) : selection.speed
            let hit = cached[cacheKey(text: line.text, selection: selection, revision: pack.revision, language: language, speed: speed)]
                ?? existing.first { $0.index == line.index && $0.text == line.text && $0.cacheKey != nil
                    && $0.cacheKey == cacheKey(text: line.text, selection: selection, revision: pack.revision, language: language, speed: $0.speed) }
            if let hit, let clip = hit.clipPath, FileManager.default.fileExists(atPath: paths.url(clip).path) {
                var reused = hit
                reused.index = line.index; reused.at = line.at; reused.until = line.until; reused.shortened = line.shortened
                out[i] = reused
                continue
            }
            var recorded = try await speak(line, language: language, selection: selection, speed: speed, a: a, paths: paths, voice: voice, usage: &usage)
            emit(.voiceUsage(before + usage))
            if let spoken = recorded.spokenEnd, spoken > allowed {
                let faster = fitSpeed(spoken: spoken, allowed: allowed, speed: speed)
                if pack.adjustsSpeed, faster > speed + 0.005 {
                    log.line(String(format: "line %d ran %.2f s for %.2f s; again at %.2f×", line.index, spoken, allowed, faster))
                    speed = faster
                    recorded = try await speak(line, language: language, selection: selection, speed: speed, a: a, paths: paths, voice: voice, usage: &usage)
                    emit(.voiceUsage(before + usage))
                }
                if let still = recorded.spokenEnd, still > allowed { long.append((line.index, still, allowed)) }
            }
            out[i] = recorded
        }
        emit(.progress(1))
        log.add(voice: usage)
        return Result(lines: out, usage: usage, long: long)
    }

    static func speak(_ line: NarrationLine, language: Language, selection: VoiceSelection, speed: Double, a: AssetPaths, paths: CampaignPaths,
                      voice: any SpeechSynthesizer, usage: inout VoiceUsage) async throws -> NarrationLine {
        let clip = try await voice.speak(SpeechRequest(text: line.text, voiceID: selection.voiceID, language: language, speed: speed))
        usage = usage + VoiceUsage(characters: line.text.count, requests: 1, seconds: clip.seconds, packID: voice.pack.id)
        let file = a.clip(language, line.index)
        try WAVFile.write(clip.samples, sampleRate: clip.sampleRate, to: file)
        var out = line
        out.spokenStart = clip.spokenStart
        out.spokenEnd = clip.spokenEnd
        out.words = clip.words
        out.clipPath = paths.relative(file)
        out.clipSeconds = clip.seconds
        out.characters = line.text.count
        out.requestID = nil
        out.speed = speed
        out.cacheKey = cacheKey(text: line.text, selection: selection, revision: voice.pack.revision, language: language, speed: speed)
        return out
    }

    /// The speed that brings `spoken` seconds (at `speed`) inside `allowed`, with 2 % to spare;
    /// never slower than now, never faster than 1.15×.
    static func fitSpeed(spoken: Double, allowed: Double, speed: Double) -> Double {
        guard allowed > 0, spoken > allowed else { return speed }
        return min(NarrationPacing.maxSpeed, max(speed, (speed * spoken / allowed * 1.02 * 100).rounded(.up) / 100))
    }

    static func cacheKey(text: String, selection: VoiceSelection, revision: String?, language: Language, speed: Double) -> String {
        ContextDigestBuilder.sha([text, selection.voiceID, selection.packID, revision ?? "", language.code, String(format: "%.2f", speed)]
            .joined(separator: "\u{1F}"))
    }
}
