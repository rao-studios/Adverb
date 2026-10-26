//
//  CampaignDesk.swift
//  Adverb
//
//  WHAT: A campaign: its header (state, plan, build, export), its month as a calendar, the day that
//        is open beside it, and the runs working on it.
//  IN:   CampaignService, GenerationService
//  OUT:  AdverbRuntimeRoot (plan, build, setState, export), DayPane
//

import AdverbAgents
import AdverbCore
import AdverbRuntime
import Combine
import Granite
import SwiftUI

struct CampaignDesk: GraniteComponent {
    @Command var center: Center
    @Relay var campaigns: CampaignService
    @Relay var generation: GenerationService
    let project: Project
    let campaignID: UUID
    let selection: DeskSelection
    @State var tick = 0
    @State var pendingLive: String?
    @State var pendingRemove = false

    init(project: Project, campaignID: UUID, selection: DeskSelection) {
        self.project = project; self.campaignID = campaignID; self.selection = selection
    }

    /// Runs stream their progress up to 60 times a second; the relay's own publisher, not the
    /// holder's 0.2 s settle, keeps the calendar's spinners and the runs strip live.
    var changed: AnyPublisher<Void, Never> {
        Publishers.Merge(_campaigns.relay.objectWillChange, _generation.relay.objectWillChange)
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .map { _ in () }.eraseToAnyPublisher()
    }

    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }
}

extension CampaignDesk {
    struct Center: GraniteCenter {
        struct State: GraniteState {}
        @Store var state: State
    }
}
