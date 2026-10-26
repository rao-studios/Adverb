//
//  Retimer.swift
//  AdverbAgents
//
//  WHAT: The agent that re-cuts a day's asset to a song (RetimeJob). One per day; asking again
//        while it works starts over with the new choice.
//

import AdverbCore
import Foundation
import Granite

public struct Retimer: GraniteAgent {
    public struct Input: Sendable {
        public var projectSlug: String
        public var campaignID: UUID
        public var dayIndex: Int
        public var request: RetimeRequest
        public init(projectSlug: String, campaignID: UUID, dayIndex: Int, request: RetimeRequest) {
            self.projectSlug = projectSlug; self.campaignID = campaignID; self.dayIndex = dayIndex; self.request = request
        }
    }

    public typealias Center = GenerationService.Center
    public typealias Event = GenerationEvent
    public typealias Compute = AdverbCompute

    public init() {}

    public static var concurrency: AgentConcurrency { .supersede }
    public static func key(_ input: Input) -> String { RunKey.beat(input.campaignID, input.dayIndex) }

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<GenerationEvent, Error> {
        let compute = context.compute
        return AgentStream.run { emit in
            try await RetimeJob.run(projectSlug: input.projectSlug, campaignID: input.campaignID, dayIndex: input.dayIndex,
                                    request: input.request, compute: compute, emit: emit)
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
