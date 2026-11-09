//
//  GenerationEvent.swift
//  AdverbAgents
//
//  WHAT: What a generation run says while it works: the step it is on, how far, what the model is
//        thinking about and writing, how much it has read and written, and the moments the campaign
//        on disk changed.
//

import AdverbCore
import Foundation

public enum GenerationEvent: Sendable, Equatable {
    case step(String)
    case progress(Double)
    /// The model's thinking, streamed.
    case activity(String)
    /// The model's answer, streamed as it is written.
    case writing(String)
    case usage(TokenUsage)
    /// What the run has spoken so far.
    case voiceUsage(VoiceUsage)
    case log(String)
    /// The plan was written: this many days.
    case planned(Int)
    /// A day's contact sheet was drawn (before campaign.json knows it): the day shows it now.
    case sheet(Int)
    /// A day's asset was written to campaign.json.
    case dayDone(Int)
    /// Something went wrong with a day but the run went on, or the run is about to fail.
    case problem(String)
}
