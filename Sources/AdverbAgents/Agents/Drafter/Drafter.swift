//
//  Drafter.swift
//  AdverbAgents
//
//  WHAT: The agent that writes one day to its contact sheet (DraftJob). Keyed by campaign and day,
//        two at a time: the model's calls take turns on the GPU, so the second day's stills and
//        sheet overlap the first day's writing. With the sheet gate off, a day whose sheet passed
//        its checks goes on to render in the same run (RenderJob).
//

import AdverbCore
import Foundation
import Granite

public struct Drafter: GraniteAgent {
    public struct Input: Sendable {
        public var projectSlug: String
        public var campaignID: UUID
        public var dayIndex: Int
        /// What the person asked to change, when they sent the sheet back.
        public var note: String?
        public init(projectSlug: String, campaignID: UUID, dayIndex: Int, note: String? = nil) {
            self.projectSlug = projectSlug; self.campaignID = campaignID; self.dayIndex = dayIndex; self.note = note
        }
    }

    public typealias Center = GenerationService.Center
    public typealias Event = GenerationEvent
    public typealias Compute = AdverbCompute

    public init() {}

    public static var concurrency: AgentConcurrency { .parallel(max: 2) }
    public static func key(_ input: Input) -> String { RunKey.build(input.campaignID, input.dayIndex) }

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<GenerationEvent, Error> {
        let compute = context.compute
        return AgentStream.run { emit in
            try await DraftJob.run(projectSlug: input.projectSlug, campaignID: input.campaignID, dayIndex: input.dayIndex, note: input.note,
                                   compute: compute, emit: emit)
            guard !compute.settings.sheetGate else { return }
            try await RenderJob.run(projectSlug: input.projectSlug, campaignID: input.campaignID, dayIndex: input.dayIndex, compute: compute, emit: emit)
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
