//
//  GenerationService.swift
//  AdverbAgents
//
//  WHAT: Claude's work, as Granite state: every run in flight or just ended (plan, build, beatmap)
//        with its step, progress, thinking and cost; and the agents that do the work.
//  OUT:  GenerationService+Center, Reducers/GenerationService.Set, Ops/GenerationOps
//  PIN:  Craft's shape. Granite owns the state; the agents' runs own the compute and never touch
//        state; each run's events are reduced on main by the agent's own reduce. The durable
//        result is campaign.json, written by the runs through CampaignLedger.
//

import Foundation
import Granite

public struct GenerationService: GraniteService {
    @Service(.online) public var center: Center
    public init() {}
}

extension GenerationService {
    /// The writer, from any thread. PIN: Granite's `send` is main-only: off main this hops.
    public func set(_ kind: Set.Meta.Kind) {
        let meta = Set.Meta(kind: kind)
        guard !Thread.isMainThread else { center.set.send(meta); return }
        let service = self
        DispatchQueue.main.async { service.center.set.send(meta) }
    }
}
