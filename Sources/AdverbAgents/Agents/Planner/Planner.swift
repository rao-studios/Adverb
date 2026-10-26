//
//  Planner.swift
//  AdverbAgents
//
//  WHAT: The agent that plans a campaign's month (PlanJob), one run per campaign; asking again
//        while it plans starts over.
//

import AdverbCore
import Foundation
import Granite

public struct Planner: GraniteAgent {
    public struct Input: Sendable {
        public var projectSlug: String
        public var campaignID: UUID
        public init(projectSlug: String, campaignID: UUID) { self.projectSlug = projectSlug; self.campaignID = campaignID }
    }

    public typealias Center = GenerationService.Center
    public typealias Event = GenerationEvent
    public typealias Compute = AdverbCompute

    public init() {}

    public static var concurrency: AgentConcurrency { .supersede }
    public static func key(_ input: Input) -> String { RunKey.plan(input.campaignID) }

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<GenerationEvent, Error> {
        let compute = context.compute
        return AgentStream.run { emit in try await PlanJob.run(projectSlug: input.projectSlug, campaignID: input.campaignID, compute: compute, emit: emit) }
    }

    public func reduce(state: inout Center.State, event: GenerationEvent, run: AgentRunID) {
        GenerationOps.event(event, key: run.key, to: &state)
    }

    public func reduce(state: inout Center.State, lifecycle: AgentLifecycle, run: AgentRunID) {
        GenerationOps.lifecycle(lifecycle.phase, message: lifecycle.message, key: run.key, to: &state)
    }

    public static func coalesce(_ a: GenerationEvent, _ b: GenerationEvent) -> GenerationEvent? { AgentStream.coalesce(a, b) }
}

extension AgentLifecycle {
    var phase: RunPhase {
        switch self {
        case .started: .running
        case .finished: .finished
        case .cancelled: .cancelled
        case .failed: .failed
        }
    }

    var message: String? { if case .failed(let m) = self { return m }; return nil }
}
