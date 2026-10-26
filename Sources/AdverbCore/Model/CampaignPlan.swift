//
//  CampaignPlan.swift
//  AdverbCore
//
//  WHAT: What the planner says about the month as a whole: the summary, the arc, what it read,
//        and what it was careful about.
//

import Foundation

public struct CampaignPlan: Codable, Sendable, Equatable, Hashable {
    public var summary: String
    public var arc: [String]
    public var sources: [String]
    public var cautions: [String]
    public var model: String
    public var plannedAt: Date

    public init(summary: String, arc: [String], sources: [String], cautions: [String], model: String, plannedAt: Date = Date()) {
        self.summary = summary; self.arc = arc; self.sources = sources; self.cautions = cautions
        self.model = model; self.plannedAt = plannedAt
    }
}
