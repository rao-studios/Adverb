//
//  GenerationOps.swift
//  AdverbAgents
//
//  WHAT: Every change to the generation state, as a pure function: what the Set reducer and the
//        agents' reduce call, and what the tests call without Granite.
//

import AdverbCore
import Foundation

public enum GenerationOps {
    public static func apply(_ kind: GenerationService.Set.Meta.Kind, to state: inout GenerationService.Center.State) {
        switch kind {
        case .clearEnded: state.runs = state.runs.filter { $0.value.phase == .running }
        case .clear(let key): state.runs.removeValue(forKey: key)
        case .notice(let text): state.notice = text
        case .problem(let text): state.problem = text
        case .touched(let id): state.revisions[id, default: 0] += 1
        }
    }

    public static func event(_ event: GenerationEvent, key: String, to state: inout GenerationService.Center.State) {
        var run = state.runs[key] ?? started(key)
        switch event {
        case .step(let name): run.step = name; run.progress = 0; run.log.append("▸ \(name)")
        case .progress(let p): run.progress = p
        case .activity(let text):
            run.activity = String((run.activity + text).suffix(600))
        case .usage(let u): run.usage = u
        case .voiceUsage(let v): run.voice = v
        case .log(let line): run.log.append(line)
        case .planned(let count):
            run.log.append("Planned \(count) days")
            if let id = run.campaignID { state.revisions[id, default: 0] += 1 }
        case .dayDone(let day):
            run.log.append("Day \(day) written")
            if let id = run.campaignID { state.revisions[id, default: 0] += 1 }
        case .problem(let text): run.message = text; run.log.append("⚠︎ \(text)")
        }
        if run.log.count > 40 { run.log.removeFirst(run.log.count - 40) }
        state.runs[key] = run
    }

    public static func lifecycle(_ phase: RunPhase, message: String?, key: String, to state: inout GenerationService.Center.State) {
        var run = state.runs[key] ?? started(key)
        run.phase = phase
        if phase == .running {
            run = started(key)
        } else {
            run.endedAt = Date()
            if phase == .finished { run.progress = 1; run.step = "Done" }
            if let message { run.message = message }
            if let id = run.campaignID { state.revisions[id, default: 0] += 1 }
        }
        state.runs[key] = run
    }

    static func started(_ key: String) -> RunProgress {
        let parsed = RunKey.parse(key)
        return RunProgress(key: key, kind: parsed.kind, campaignID: parsed.campaign, dayIndex: parsed.day)
    }
}
