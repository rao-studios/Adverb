//
//  Settings.swift
//  Adverb
//
//  WHAT: Settings: a sidebar of pages and the open page.
//  IN:   ConfigService
//  OUT:  AdverbRuntimeRoot (update, saveKey, forgetKey, testKey, chooseWorkdir, checkToolchain)
//

import AdverbRuntime
import Combine
import Granite
import SwiftUI

struct Settings: GraniteComponent {
    @Command var center: Center
    @Relay var config: ConfigService
    let navigation: SettingsNavigation
    @State var tick = 0
    @State var keyDraft = ""

    init(navigation: SettingsNavigation) { self.navigation = navigation }

    var configChanged: ObservableObjectPublisher { _config.relay.objectWillChange }
}

extension Settings {
    struct Center: GraniteCenter {
        struct State: GraniteState {}
        @Store var state: State
    }
}
