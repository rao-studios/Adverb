//
//  Builder.swift
//  AdverbAgents
//
//  WHAT: The agent that builds one day's asset (BuildJob). Keyed by campaign and day, two at a
//        time: Claude writes pages in parallel, renders take turns (RenderGate).
//

import AdverbCore
import Foundation
import Granite

public struct Builder: GraniteAgent {
    public struct Input: Sendable {
        public var projectSlug: String
        public var campaignID: UUID
        public var dayIndex: Int
        public init(projectSlug: String, campaignID: UUID, dayIndex: Int) {
            self.projectSlug = projectSlug; self.campaignID = campaignID; self.dayIndex = dayIndex
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
            try await BuildJob.run(projectSlug: input.projectSlug, campaignID: input.campaignID, dayIndex: input.dayIndex, compute: compute, emit: emit)
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
