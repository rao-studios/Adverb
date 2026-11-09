//
//  SettingsSection.swift
//  Adverb
//
//  WHAT: A page of Settings (Craft's SettingsSection).
//

import Foundation

enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general, models, voice, rendering, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .models: "Models"
        case .voice: "Voice"
        case .rendering: "Rendering"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Where Adverb keeps its projects, and where your songs are."
        case .models: "The models on this Mac that plan, write and look, and how they work on a campaign."
        case .voice: "A voice on this Mac narrates each asset; after you confirm a day's English, it speaks the languages it can."
        case .rendering: "How pages become videos: quality, speed, and the optional Chrome path."
        case .about: "This build of Adverb."
        }
    }

    var symbol: String {
        switch self {
        case .general: "folder"
        case .models: "cpu"
        case .voice: "waveform"
        case .rendering: "film"
        case .about: "info.circle"
        }
    }
}
