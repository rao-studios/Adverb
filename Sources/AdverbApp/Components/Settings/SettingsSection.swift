//
//  SettingsSection.swift
//  Adverb
//
//  WHAT: A page of Settings (Craft's SettingsSection).
//

import Foundation

enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general, claude, rendering, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .claude: "Claude"
        case .rendering: "Rendering"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Where Adverb keeps its projects, and where your songs are."
        case .claude: "The key, the model and how it works on a campaign."
        case .rendering: "How pages become videos: quality, speed, and the optional Chrome path."
        case .about: "This build of Adverb."
        }
    }

    var symbol: String {
        switch self {
        case .general: "folder"
        case .claude: "sparkles"
        case .rendering: "film"
        case .about: "info.circle"
        }
    }
}
