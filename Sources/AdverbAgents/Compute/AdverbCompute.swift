//
//  AdverbCompute.swift
//  AdverbAgents
//
//  WHAT: What an agent's run computes with, resolved by the composition root when a run starts
//        (`$agent.attach`): the Claude client with the person's key and model, the ElevenLabs
//        client when there is a key for it, the prompts, the workspace on the drive, and the
//        settings of the moment.
//

import AdverbCore
import Foundation

public struct AdverbCompute: Sendable {
    public let client: ClaudeClient
    public let prompts: PromptLibrary
    public let workspace: Workspace
    public let settings: AdverbSettings
    /// Nil without an ElevenLabs key: a narrated build then finishes silent and says why.
    public let voice: ElevenLabsClient?

    public init(client: ClaudeClient, prompts: PromptLibrary, workspace: Workspace, settings: AdverbSettings, voice: ElevenLabsClient? = nil) {
        self.client = client; self.prompts = prompts; self.workspace = workspace; self.settings = settings; self.voice = voice
    }

    public func project(_ slug: String) throws -> Project {
        try JSONCoding.read(Project.self, from: workspace.projectFile(slug))
    }

    public func paths(_ project: Project, _ campaignID: UUID) -> CampaignPaths {
        CampaignPaths(workspace: workspace, projectSlug: project.slug, campaignID: campaignID)
    }

    public var kitFolder: (Project) -> URL {
        { [workspace] project in workspace.projectFolder(project.slug).appendingPathComponent("kit", isDirectory: true) }
    }

    /// The campaign's frozen digest, made (and frozen) when it is not there yet.
    public func digest(_ project: Project, paths: CampaignPaths, refresh: Bool = false) throws -> (text: String, hash: String) {
        if !refresh, let text = try? String(contentsOf: paths.digestFile, encoding: .utf8), !text.isEmpty {
            return (text, ContextDigestBuilder.sha(text))
        }
        let digest = ContextDigestBuilder.build(root: project.contextURL)
        try AtomicFile.write(digest.text, to: paths.digestFile)
        return (digest.text, digest.sha256)
    }

    /// Web fetch for the app's own site and repo, when allowed.
    public func tools(for project: Project) -> [JSONValue] {
        guard settings.webFetch else { return [] }
        let hosts = project.app.sources.compactMap { URL(string: $0)?.host }
        guard !hosts.isEmpty else { return [] }
        return [ClaudeRequest.webFetch(domains: Array(Set(hosts + ["rao.nyc"])).sorted())]
    }
}
