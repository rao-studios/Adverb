//
//  CampaignLedger.swift
//  AdverbCore
//
//  WHAT: The one writer of campaign.json files. Builders run side by side and each finishes a
//        day: each update re-reads the file, applies its change and writes it back, one at a time,
//        so two days finishing together never lose each other.
//

import Foundation

public actor CampaignLedger {
    public static let shared = CampaignLedger()

    public init() {}

    @discardableResult
    public func update(_ paths: CampaignPaths, _ change: @Sendable (inout Campaign) throws -> Void) throws -> Campaign {
        var campaign = try JSONCoding.read(Campaign.self, from: paths.campaignFile)
        try change(&campaign)
        campaign.updatedAt = Date()
        try JSONCoding.write(campaign, to: paths.campaignFile)
        return campaign
    }

    public func read(_ paths: CampaignPaths) throws -> Campaign {
        try JSONCoding.read(Campaign.self, from: paths.campaignFile)
    }

    /// One day, changed in place.
    @discardableResult
    public func updateDay(_ paths: CampaignPaths, index: Int, _ change: @Sendable (inout CampaignDay) -> Void) throws -> Campaign {
        try update(paths) { campaign in
            guard var day = campaign.day(index) else { throw CampaignError.noDay(index) }
            change(&day)
            campaign.update(day)
        }
    }
}
