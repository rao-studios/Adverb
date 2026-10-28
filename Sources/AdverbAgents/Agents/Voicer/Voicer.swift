//
//  Voicer.swift
//  AdverbAgents
//
//  WHAT: The agent that gives a built day its voice-over (VoiceJob): the English, in a voice the
//        person picked, or the languages after the English is confirmed. One run per day; asking
//        again while it works starts over (every clip it already made is kept on disk).
//

import AdverbCore
import Foundation
import Granite

public enum VoiceTask: Sendable, Equatable {
    /// The English narration in `voice`; `rescript` asks Claude for new lines first.
    case english(VoiceSelection, rescript: Bool = false)
    /// The confirmed English in these languages.
    case languages([Language])
}

public struct Voicer: GraniteAgent {
    public struct Input: Sendable {
        public var projectSlug: String
        public var campaignID: UUID
        public var dayIndex: Int
        public var task: VoiceTask
        public init(projectSlug: String, campaignID: UUID, dayIndex: Int, task: VoiceTask) {
            self.projectSlug = projectSlug; self.campaignID = campaignID; self.dayIndex = dayIndex; self.task = task
        }
    }

    public typealias Center = GenerationService.Center
    public typealias Event = GenerationEvent
    public typealias Compute = AdverbCompute

    public init() {}

    public static var concurrency: AgentConcurrency { .parallel(max: 2) }
    public static func key(_ input: Input) -> String { RunKey.voice(input.campaignID, input.dayIndex) }

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<GenerationEvent, Error> {
        let compute = context.compute
        return AgentStream.run { emit in
            try await VoiceJob.run(projectSlug: input.projectSlug, campaignID: input.campaignID, dayIndex: input.dayIndex,
                                   task: input.task, compute: compute, emit: emit)
        }
    }

    public func reduce(state: inout Center.State, event: GenerationEvent, run: AgentRunID) {
        GenerationOps.event(event, key: run.key, to: &state)
    }

    public func reduce(state: inout Center.State, lifecycle: AgentLifecycle, run: AgentRunID) {
        GenerationOps.lifecycle(lifecycle.phase, message: lifecycle.message, key: run.key, to: &state)
    }

    public static func coalesce(_ a: GenerationEvent, _ b: GenerationEvent) -> GenerationEvent? { AgentStream.coalesce(a, b) }
}
