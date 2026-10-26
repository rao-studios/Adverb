//
//  Desk.swift
//  Adverb
//
//  WHAT: The detail column: the selected campaign, else the selected project, else a welcome.
//

import AdverbRuntime
import Combine
import Granite
import SwiftUI

struct Desk: GraniteComponent {
    @Command var center: Center
    @Relay var projects: ProjectService
    @Relay var campaigns: CampaignService
    @Relay var config: ConfigService
    let selection: DeskSelection
    @State var tick = 0

    init(selection: DeskSelection) { self.selection = selection }

    var changed: AnyPublisher<Void, Never> {
        Publishers.Merge3(_projects.relay.objectWillChange, _campaigns.relay.objectWillChange, _config.relay.objectWillChange)
            .map { _ in () }.eraseToAnyPublisher()
    }
}

extension Desk {
    struct Center: GraniteCenter {
        struct State: GraniteState {}
        @Store var state: State
    }
}
