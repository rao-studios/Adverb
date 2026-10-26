//
//  SettingsNavigation.swift
//  Adverb
//
//  WHAT: Which Settings page is open: the window's own (Craft's SettingsNavigation).
//

import Observation

@MainActor
@Observable
final class SettingsNavigation {
    var section: SettingsSection = .general
}
