//
//  VoicePicker.swift
//  Adverb
//
//  WHAT: ElevenLabs' voices to choose from: searched by name, accent or use, each with its labels
//        and a play button that previews it. Used by Settings › Voice, the new campaign sheet and
//        the voice sheet.
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
    let selectedID: String?
    let height: CGFloat
    let onPick: (ElevenVoice) -> Void
    @State var query = ""
    @State var tick = 0

    init(selectedID: String?, height: CGFloat = AdverbLayout.voiceList.regular, onPick: @escaping (ElevenVoice) -> Void) {
        self.selectedID = selectedID; self.height = height; self.onPick = onPick
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
        let voices = state.voices.filter { $0.matches(query) }
        return VStack(alignment: .leading, spacing: .layer2) {
            HStack(spacing: .layer2) {
                AdverbTextField(placeholder: "Search by name, accent or use", text: $query)
                if state.loading { ProgressView().controlSize(.small) }
                Button("Reload") { Task { await root.loadVoices(force: true) } }.buttonStyle(.adverbLink).disabled(state.loading)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: .layer1) {
                    ForEach(voices) { v in
                        VoiceRow(voice: v, selected: v.id == selectedID, previewing: state.previewing == v.id, cached: state.cached.contains(v.id),
                                 pick: { onPick(v) }, preview: { Task { await root.previewVoice(v.id) } })
                    }
                    if voices.isEmpty, !state.loading {
                        Text(state.problem ?? (state.voices.isEmpty ? "No voices yet." : "No voice matches “\(query)”."))
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
    let voice: ElevenVoice
    let selected: Bool
    let previewing: Bool
    let cached: Bool
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
                        if !voice.summary.isEmpty { Text(voice.summary).adverbType(.caption).foregroundStyle(Color.adverbInkDim).lineLimit(1) }
                        if let description = voice.description, !description.isEmpty {
                            Text(description).adverbType(.fine).foregroundStyle(Color.adverbInkMuted).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: preview) {
                    Image(systemName: previewing ? "stop.circle.fill" : "play.circle")
                        .font(.adverbGlyph(AdverbGlyph.heading))
                        .foregroundStyle(previewing ? Color.adverbGold : Color.adverbInkSoft)
                }
                .buttonStyle(.plain)
                .disabled(voice.previewURL == nil && !cached)
                .help(previewing ? "Stop" : "Hear \(voice.name)")
            }
        }
    }
}
