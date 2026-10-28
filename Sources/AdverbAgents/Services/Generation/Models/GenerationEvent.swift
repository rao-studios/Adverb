//
//  GenerationEvent.swift
//  AdverbAgents
//
//  WHAT: What a generation run says while it works: the step it is on, how far, what Claude is
//        thinking about, what it has cost, and the moments the campaign on disk changed.
//

import AdverbCore
import Foundation

public enum GenerationEvent: Sendable, Equatable {
    case step(String)
    case progress(Double)
    /// A thinking summary or a tool note, streamed.
    case activity(String)
    case usage(TokenUsage)
    /// What the run has spent at ElevenLabs so far.
    case voiceUsage(VoiceUsage)
    case log(String)
    /// The plan was written: this many days.
    case planned(Int)
    /// A day's asset was written to campaign.json.
    case dayDone(Int)
    /// Something went wrong with a day but the run went on, or the run is about to fail.
    case problem(String)
}
