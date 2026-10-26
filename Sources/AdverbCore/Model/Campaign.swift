//
//  Campaign.swift
//  AdverbCore
//
//  WHAT: A month of posts for one project: the brief it was made from, the plan Claude wrote, and
//        every day with its asset. campaign.json is the single source of truth for all of it.
//  PIN:  One live campaign per project (CampaignStore enforces it). Draft is where a campaign is
//        planned and built; live is the month being posted; archived is a month that is over.
//

import Foundation

public enum CampaignState: String, Codable, Sendable, CaseIterable, Hashable {
    case draft, live, archived
    public var title: String { rawValue.capitalized }
}

public struct Campaign: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var version: Int = 1
    public var id: UUID
    public var projectID: UUID
    public var name: String
    public var state: CampaignState
    public var brief: CampaignBrief
    public var plan: CampaignPlan?
    public var days: [CampaignDay]
    /// The digest the plan was made from; builds reuse the same bytes so the prompt cache hits.
    public var contextDigestHash: String?
    public var lastRunID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var wentLiveAt: Date?
    public var archivedAt: Date?

    public init(id: UUID = UUID(), projectID: UUID, name: String, brief: CampaignBrief, state: CampaignState = .draft,
                createdAt: Date = Date()) {
        self.id = id; self.projectID = projectID; self.name = name; self.state = state; self.brief = brief
        self.plan = nil; self.days = []; self.contextDigestHash = nil; self.lastRunID = nil
        self.createdAt = createdAt; self.updatedAt = createdAt; self.wentLiveAt = nil; self.archivedAt = nil
    }

    public func day(_ index: Int) -> CampaignDay? { days.first { $0.index == index } }

    public mutating func update(_ day: CampaignDay) {
        if let i = days.firstIndex(where: { $0.index == day.index }) { days[i] = day } else { days.append(day); days.sort { $0.index < $1.index } }
    }

    public var builtCount: Int { days.filter { $0.asset != nil }.count }
    public var postedCount: Int { days.filter { $0.status == .posted }.count }
    public var isPlanned: Bool { plan != nil && !days.isEmpty }
}
