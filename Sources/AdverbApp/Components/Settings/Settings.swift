//
//  Settings.swift
//  Adverb
//
//  WHAT: Settings: a sidebar of pages and the open page.
//  IN:   ConfigService, ModelService, VoiceService
//  OUT:  AdverbRuntimeRoot (update, the model actions, chooseWorkdir, checkToolchain)
//

import AdverbRuntime
import Combine
import Granite
import SwiftUI

struct Settings: GraniteComponent {
    @Command var center: Center
    @Relay var config: ConfigService
    @Relay var models: ModelService
    @Relay var voices: VoiceService
    let navigation: SettingsNavigation
    @State var tick = 0

    init(navigation: SettingsNavigation) { self.navigation = navigation }

    var configChanged: ObservableObjectPublisher { _config.relay.objectWillChange }
    var modelsChanged: ObservableObjectPublisher { _models.relay.objectWillChange }
    var voicesChanged: ObservableObjectPublisher { _voices.relay.objectWillChange }
}

extension Settings {
    struct Center: GraniteCenter {
        struct State: GraniteState {}
        @Store var state: State
    }
}
