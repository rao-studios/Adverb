//
//  DeskSelection.swift
//  Adverb
//
//  WHAT: What the main window is showing: the project, the campaign, the day, which sheet is up.
//        The window's own; never a service (Craft's WindowSelection).
//

import Foundation
import Observation

enum DeskSheet: Identifiable, Equatable {
    case newProject
    case manageProject(String)
    case newCampaign(String)
    case music(slug: String, campaign: UUID, day: Int)
    case voice(slug: String, campaign: UUID, day: Int)
    case campaignVoice(slug: String, campaign: UUID)

    var id: String {
        switch self {
        case .newProject: "new-project"
        case .manageProject(let s): "manage-\(s)"
        case .newCampaign(let s): "new-campaign-\(s)"
        case .music(_, let c, let d): "music-\(c)-\(d)"
        case .voice(_, let c, let d): "voice-\(c)-\(d)"
        case .campaignVoice(_, let c): "campaign-voice-\(c)"
        }
    }
}

@MainActor
@Observable
final class DeskSelection {
    var projectSlug: String?
    var campaignID: UUID?
    var dayIndex: Int?
    var sheet: DeskSheet?
    var showRuns = true
    /// The orientation the day pane plays.
    var orientation: String = "portrait"
    /// The language the day pane plays ("en", or a voice-over's language code).
    var language: String = "en"

    func select(project slug: String?) {
        guard slug != projectSlug else { campaignID = nil; dayIndex = nil; return }
        projectSlug = slug; campaignID = nil; dayIndex = nil
    }

    func select(campaign id: UUID, in slug: String) {
        if projectSlug != slug { projectSlug = slug }
        if campaignID != id { dayIndex = nil; language = "en" }
        campaignID = id
    }
}
