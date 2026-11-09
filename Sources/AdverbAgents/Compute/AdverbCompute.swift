//
//  AdverbCompute.swift
//  AdverbAgents
//
//  WHAT: What an agent's run computes with, resolved by the composition root when a run starts
//        (`$agent.attach`): the writer (a language model on this Mac), the eyes (the writer itself
//        when it reads images, else a vision model, else none), the voices (the packs on this Mac,
//        when there are any), the prompts, the workspace on the drive, and the settings of the
//        moment.
//  PIN:  The models are handles: nothing is loaded until a run first asks one to write (AdverbModels
//        loads on first use and keeps it). A warp-only re-cut or a voice step never loads the writer.
//

import AdverbCore
import Foundation

public struct AdverbCompute: Sendable {
    public let text: any LanguageModel
    /// Nil: no model here can read the stills, and the review pass is skipped.
    public let vision: (any LanguageModel)?
    /// Nil without a voice pack: a narrated day then finishes silent and says why.
    public let voice: (any SpeechProvider)?
    public let prompts: PromptLibrary
    public let workspace: Workspace
    public let settings: AdverbSettings

    public init(text: any LanguageModel, vision: (any LanguageModel)? = nil, voice: (any SpeechProvider)? = nil, prompts: PromptLibrary,
                workspace: Workspace, settings: AdverbSettings) {
        self.text = text; self.vision = vision; self.voice = voice; self.prompts = prompts; self.workspace = workspace; self.settings = settings
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

    /// How much of the project the writer reads: its context less the system prompt, a page's
    /// answer and room to spare; never more than the digest's own cap.
    public var digestBudget: Int {
        max(4_000, min(60_000, text.info.contextTokens - 12_500 - 24_000 - 2_000))
    }

    /// The campaign's frozen digest, made (and frozen) when it is not there yet.
    public func digest(_ project: Project, paths: CampaignPaths, refresh: Bool = false) throws -> (text: String, hash: String) {
        if !refresh, let text = try? String(contentsOf: paths.digestFile, encoding: .utf8), !text.isEmpty {
            return (text, ContextDigestBuilder.sha(text))
        }
        let digest = ContextDigestBuilder.build(root: project.contextURL, budgetTokens: digestBudget,
                                                readmeTokens: min(16_000, digestBudget / 2))
        try AtomicFile.write(digest.text, to: paths.digestFile)
        return (digest.text, digest.sha256)
    }

    /// How the writer thinks for a step that benefits (the plan, a page).
    public var thinking: ThinkingMode {
        settings.thinking && text.info.thinks ? .on(budget: settings.thinkingBudget) : .off
    }

    /// The eyes the review pass runs on, when the setting is on.
    public var reviewer: (any LanguageModel)? { settings.reviewPass ? vision : nil }
}
