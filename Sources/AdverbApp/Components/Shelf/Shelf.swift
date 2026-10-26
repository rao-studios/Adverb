//
//  Shelf.swift
//  Adverb
//
//  WHAT: The sidebar: every project (its label, its name), with its campaigns under it (state,
//        progress); new project and new campaign; a project's menu (manage, reveal, remove).
//  IN:   ProjectService, CampaignService, GenerationService (what is running)
//

import AdverbAgents
import AdverbRuntime
import Combine
import Granite
import SwiftUI

struct Shelf: GraniteComponent {
    @Command var center: Center
    @Relay var projects: ProjectService
    @Relay var campaigns: CampaignService
    @Relay var generation: GenerationService
    let selection: DeskSelection
    @State var tick = 0

    init(selection: DeskSelection) { self.selection = selection }

    var changed: AnyPublisher<Void, Never> {
        Publishers.Merge3(_projects.relay.objectWillChange, _campaigns.relay.objectWillChange, _generation.relay.objectWillChange)
            .map { _ in () }.eraseToAnyPublisher()
    }
}
