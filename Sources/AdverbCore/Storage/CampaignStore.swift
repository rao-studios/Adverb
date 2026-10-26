//
//  CampaignStore.swift
//  AdverbCore
//
//  WHAT: A project's campaigns: list, create a draft, save, change state, remove.
//  PIN:  One live campaign per project: going live while another is live throws
//        `anotherIsLive`, and the UI offers to archive that one first.
//

import Foundation

public struct CampaignStore: Sendable {
    public let workspace: Workspace
    public let project: Project

    public init(workspace: Workspace, project: Project) { self.workspace = workspace; self.project = project }

    public var folder: URL { workspace.projectFolder(project.slug).appendingPathComponent("campaigns", isDirectory: true) }

    public func paths(_ id: UUID) -> CampaignPaths { CampaignPaths(workspace: workspace, projectSlug: project.slug, campaignID: id) }

    public func list() -> [Campaign] {
        AtomicFile.contents(of: folder)
            .filter(AtomicFile.isDirectory)
            .compactMap { try? JSONCoding.read(Campaign.self, from: $0.appendingPathComponent("campaign.json")) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func load(_ id: UUID) throws -> Campaign {
        try JSONCoding.read(Campaign.self, from: paths(id).campaignFile)
    }

    public func create(name: String, brief: CampaignBrief) throws -> Campaign {
        let campaign = Campaign(projectID: project.id, name: name, brief: brief)
        try save(campaign)
        return campaign
    }

    public func save(_ campaign: Campaign) throws {
        var campaign = campaign
        campaign.updatedAt = Date()
        try JSONCoding.write(campaign, to: paths(campaign.id).campaignFile)
    }

    public func setState(_ id: UUID, to state: CampaignState) throws -> Campaign {
        var campaign = try load(id)
        if state == .live, let other = list().first(where: { $0.state == .live && $0.id != id }) {
            throw CampaignError.anotherIsLive(other.name)
        }
        campaign.state = state
        switch state {
        case .live: campaign.wentLiveAt = Date(); campaign.archivedAt = nil
        case .archived: campaign.archivedAt = Date()
        case .draft: break
        }
        try save(campaign)
        return campaign
    }

    public func remove(_ id: UUID) throws {
        let root = paths(id).root
        precondition(root.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/"))
        if AtomicFile.isDirectory(root) { try FileManager.default.removeItem(at: root) }
    }
}

public enum CampaignError: Error, Equatable, CustomStringConvertible {
    case anotherIsLive(String)
    case notPlanned
    case noDay(Int)

    public var description: String {
        switch self {
        case .anotherIsLive(let name): "“\(name)” is live. Archive it first: a project runs one live campaign at a time."
        case .notPlanned: "Plan the campaign first."
        case .noDay(let index): "There is no day \(index) in this campaign."
        }
    }
}
