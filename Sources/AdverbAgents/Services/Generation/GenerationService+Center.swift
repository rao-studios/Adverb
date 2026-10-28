//
//  GenerationService+Center.swift
//  AdverbAgents
//

import Foundation
import Granite

extension GenerationService {
    public struct Center: GraniteCenter {
        public init() {}

        public struct State: TransientState {
            public var runs: [String: RunProgress] = [:]
            /// Bumped whenever a run changed a campaign on disk, per campaign: what the calendar
            /// watches to read campaign.json again.
            public var revisions: [UUID: Int] = [:]
            public var notice: String?
            public var problem: String?
            public init() {}

            public var active: [RunProgress] { runs.values.filter { $0.phase == .running }.sorted { $0.startedAt < $1.startedAt } }
            public var recent: [RunProgress] { runs.values.sorted { $0.startedAt > $1.startedAt } }
            public func runs(for campaign: UUID) -> [RunProgress] { recent.filter { $0.campaignID == campaign } }
            public func isBusy(_ campaign: UUID) -> Bool { active.contains { $0.campaignID == campaign } }
        }

        @Event public var set: Set.Reducer

        /// The month: one plan per campaign; a second ask replaces the first.
        @Agent public var planner: Planner.Agent
        /// One day's asset each, two at a time (Claude in parallel; renders take turns).
        @Agent(.parallel(max: 2)) public var builder: Builder.Agent
        /// A day re-cut to a song.
        @Agent public var retimer: Retimer.Agent
        /// A day's voice-over, English or more languages. One per day (a second ask replaces the
        /// first); two days at a time, the rest wait their turn.
        @Agent(.parallel(max: 2)) public var voicer: Voicer.Agent

        @Store public var state: State
    }
}
