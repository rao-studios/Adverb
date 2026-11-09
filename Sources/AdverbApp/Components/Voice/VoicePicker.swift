//
//  VoicePicker.swift
//  Adverb
//
//  WHAT: The voices on this Mac to choose from, pack by pack: searched by name or accent, each with
//        a play button that speaks a sentence in it (made on this Mac the first time, then kept).
//        Used by Settings › Voice, the new campaign sheet and the voice sheets.
//  IN:   VoiceService
//  OUT:  AdverbRuntimeRoot (loadVoices, previewVoice, stopPreview); the pick, to its caller
//

import AdverbCore
import AdverbRuntime
import Combine
import Granite
import SwiftUI

struct VoicePicker: GraniteComponent {
    @Command var center: Center
    @Relay var voice: VoiceService
    let selectedPack: String?
    let selectedID: String?
    let height: CGFloat
    let onPick: (SpeechVoice) -> Void
    @State var query = ""
    @State var tick = 0

    init(selectedPack: String?, selectedID: String?, height: CGFloat = AdverbLayout.voiceList.regular, onPick: @escaping (SpeechVoice) -> Void) {
        self.selectedPack = selectedPack; self.selectedID = selectedID; self.height = height; self.onPick = onPick
    }

    var voiceChanged: ObservableObjectPublisher { _voice.relay.objectWillChange }
}

extension VoicePicker {
    struct Center: GraniteCenter {
        struct State: GraniteState {}
        @Store var state: State
    }
}

extension VoicePicker {
    var view: some View {
        let root = AdverbRuntimeRoot.shared
        let state = voice.state
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return VStack(alignment: .leading, spacing: .layer2) {
            AdverbTextField(placeholder: "Search by name or accent", text: $query)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: .layer1) {
                    ForEach(state.packs) { pack in
                        let voices = pack.voices.filter { q.isEmpty || $0.summary.lowercased().contains(q) || $0.id.contains(q) }
                        if !voices.isEmpty {
                            Text(pack.title).adverbType(.section).foregroundStyle(Color.adverbInkMuted).padding(.top, .snug)
                            ForEach(voices) { v in
                                let tag = VoiceService.Center.State.tag(v)
                                VoiceRow(voice: v, selected: v.id == selectedID && (selectedPack == nil || v.packID == selectedPack),
                                         previewing: state.previewing == tag, preparing: state.preparing == tag,
                                         pick: { onPick(v) }, preview: { Task { await root.previewVoice(pack: v.packID, voice: v.id) } })
                            }
                        }
                    }
                    if state.voices.isEmpty {
                        Text(state.problem ?? "No voice is on this Mac yet. Download one in Settings › Voice.")
                            .adverbType(.caption).foregroundStyle(state.problem == nil ? Color.adverbInkDim : Color.adverbError)
                            .padding(.layer3)
                    }
                }
                .padding(.layer1)
            }
            .frame(height: height)
            .background(Color.adverbSidebar, in: RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous))
        }
        .onReceive(voiceChanged) { _ in tick &+= 1 }
        .task { await root.loadVoices() }
        .onDisappear { root.stopPreview() }
    }
}

/// One voice: who it sounds like, and a button to hear it.
struct VoiceRow: View {
    let voice: SpeechVoice
    let selected: Bool
    let previewing: Bool
    let preparing: Bool
    let pick: () -> Void
    let preview: () -> Void

    var body: some View {
        RowCard(selected: selected) {
            HStack(spacing: .layer2) {
                Button(action: pick) {
                    VStack(alignment: .leading, spacing: .hairline) {
                        HStack(spacing: .layer1) {
                            Text(voice.name).adverbType(.labelStrong).lineLimit(1)
                            if selected { Image(systemName: "checkmark").font(.adverbGlyph(AdverbGlyph.small, weight: .semibold)).foregroundStyle(Color.adverbGold) }
                        }
                        Text([voice.accent, voice.gender, voice.id].filter { !$0.isEmpty }.joined(separator: " · "))
                            .adverbType(.caption).foregroundStyle(Color.adverbInkDim).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if preparing {
                    ProgressView().controlSize(.small).help("Speaking a sample on this Mac")
                } else {
                    Button(action: preview) {
                        Image(systemName: previewing ? "stop.circle.fill" : "play.circle")
                            .font(.adverbGlyph(AdverbGlyph.heading))
                            .foregroundStyle(previewing ? Color.adverbGold : Color.adverbInkSoft)
                    }
                    .buttonStyle(.plain)
                    .help(previewing ? "Stop" : "Hear \(voice.name)")
                }
            }
        }
    }
}
