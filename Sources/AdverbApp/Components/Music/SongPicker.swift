//
//  SongPicker.swift
//  Adverb
//
//  WHAT: Cutting a day's asset to a song: the library (the music folder, songs added one by one),
//        the chosen song's beats, where in it the asset starts, how the page meets the beat, and
//        Apply, which re-renders both orientations with the song and overwrites the asset (the
//        silent original is kept).
//  IN:   MusicService (songs, grids), the day (CampaignService)
//  OUT:  AdverbRuntimeRoot (analyze, beatmap), SongPreview
//

import AdverbAgents
import AdverbCore
import AdverbRender
import AdverbRuntime
import Combine
import Granite
import SwiftUI

struct SongPicker: GraniteComponent {
    @Command var center: Center
    @Relay var music: MusicService
    let slug: String
    let campaignID: UUID
    let dayIndex: Int
    let selection: DeskSelection
    @State var tick = 0
    @State var chosen: Song?
    @State var inPoint: Double = 0
    @State var octave: Double = 1
    @State var nudge = 0
    @State var mode: BeatmapMode = .warp
    @State var gainDB: Double = -3
    @State var fadeOut: Double = 1.2
    @State var previewing = false

    init(slug: String, campaignID: UUID, dayIndex: Int, selection: DeskSelection) {
        self.slug = slug; self.campaignID = campaignID; self.dayIndex = dayIndex; self.selection = selection
    }

    var musicChanged: ObservableObjectPublisher { _music.relay.objectWillChange }

    var day: CampaignDay? { AdverbRuntimeRoot.shared.campaigns.state.campaign(campaignID)?.day(dayIndex) }
    var duration: Double { Double(day?.topic.duration ?? 15) }
}

extension SongPicker {
    struct Center: GraniteCenter {
        struct State: GraniteState {}
        @Store var state: State
    }
}
