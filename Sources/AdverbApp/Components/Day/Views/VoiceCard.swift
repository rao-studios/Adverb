//
//  VoiceCard.swift
//  Adverb
//
//  WHAT: A day's voice-over. Silent: add one. Narrated: the voice, the lines with their times and
//        a play button each, and Confirm English. Confirmed: the languages to make (the saved
//        preference, a check on those made), Generate, and a row per language made.
//  OUT:  the voice sheet, AdverbRuntimeRoot (confirmEnglish, languages, update, playClip)
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct VoiceCard: View {
    let asset: Asset
    let paths: CampaignPaths
    let busy: Bool
    let choose: () -> Void
    let confirm: () -> Void
    let generate: ([Language]) -> Void
    @State private var languages: [Language] = []
    @State private var playing: String?

    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                HStack {
                    SectionLabel("Voice-over")
                    Spacer()
                    if asset.voiceOver?.isConfirmed == true { AdverbBadge(text: "English confirmed", color: .adverbSuccess) }
                }
                if let vo = asset.voiceOver {
                    narrated(vo)
                } else {
                    Text("Silent. A voice-over has Claude write a short narration for this asset and an ElevenLabs voice speak it over both videos; the frames stay as they are.")
                        .adverbType(.readingSmall).foregroundStyle(Color.adverbInkDim)
                    Button("Add a voice-over…", action: choose).buttonStyle(.adverb).disabled(busy)
                }
            }
        }
        .onAppear { languages = root.settings.voiceLanguages }
        .onDisappear { if playing != nil { root.stopPreview() } }
    }

    @ViewBuilder private func narrated(_ vo: VoiceOver) -> some View {
        let english = vo.english
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: .hairline) {
                Text(vo.voiceName).adverbType(.heading)
                Text("\(Self.modelTitle(vo.modelID)) · \(english.lines.count) lines · \(english.characters.formatted()) characters")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
            Spacer()
            if vo.isConfirmed { Button("Another voice…", action: choose).buttonStyle(.adverbLink).disabled(busy) }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: .layer1) {
                ForEach(english.lines, id: \.index) { line in
                    HStack(alignment: .firstTextBaseline, spacing: .layer2) {
                        Text(String(format: "%.1f s", line.placedStart(warp: asset.warp))).adverbType(.codeSmall).foregroundStyle(Color.adverbInkMuted)
                            .frame(width: AdverbLayout.timeColumn, alignment: .leading)
                        Text(line.text).adverbType(.readingSmall).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        clipButton(line, tag: "en:\(line.index)")
                    }
                }
            }
        }
        .frame(maxHeight: AdverbLayout.voiceLines)
        if !vo.isConfirmed {
            HStack {
                Button("Confirm English", action: confirm).buttonStyle(.adverbGold)
                    .disabled(busy || english.lines.isEmpty || !english.lines.allSatisfy(\.isRecorded))
                Button("Another voice…", action: choose).buttonStyle(.adverbQuiet).disabled(busy)
            }
            Text("Listen through first: the languages are translated from these words and spoken in this voice.")
                .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
        } else {
            languagesSection(vo)
        }
    }

    @ViewBuilder private func languagesSection(_ vo: VoiceOver) -> some View {
        let made = Set(vo.freshLanguages)
        let missing = languages.filter { !made.contains($0) }
        SectionLabel("Languages")
        LanguageChips(selected: languages, mark: { made.contains($0) }, disabled: busy) { chosen in
            languages = chosen
            root.update { $0.voiceLanguages = chosen }
        }
        HStack(spacing: .layer2) {
            Button(missing.isEmpty ? (languages.isEmpty ? "Choose languages" : "All made") : "Generate \(missing.count) \(missing.count == 1 ? "language" : "languages")") {
                generate(missing)
            }
            .buttonStyle(.adverbGold).disabled(busy || missing.isEmpty)
            Text("Your choice is kept for every day.").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
        }
        ForEach(vo.languages, id: \.language) { track in
            HStack(spacing: .layer2) {
                Text(track.language.title).adverbType(.labelStrong)
                if track.stale { AdverbBadge(text: "English changed", color: .adverbWarning) }
                Text(track.isFresh ? "\(track.lines.count) lines · \(track.characters.formatted()) characters" : (track.stale ? "Generate again" : "Not mixed yet"))
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                Spacer()
                if let first = track.lines.first, track.isFresh { clipButton(first, tag: "\(track.language.code):\(first.index)") }
                Button("Regenerate") { generate([track.language]) }.buttonStyle(.adverbLink).disabled(busy)
            }
        }
    }

    @ViewBuilder private func clipButton(_ line: NarrationLine, tag: String) -> some View {
        if let clip = line.clipPath {
            Button {
                if playing == tag { root.stopPreview(); playing = nil; return }
                root.playClip(paths.url(clip), as: tag)
                playing = tag
                let seconds = line.clipSeconds ?? max(1, line.window)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64((seconds + 0.2) * 1_000_000_000))
                    if playing == tag { playing = nil }
                }
            } label: {
                Image(systemName: playing == tag ? "stop.circle.fill" : "play.circle")
                    .font(.adverbGlyph(AdverbGlyph.body))
                    .foregroundStyle(playing == tag ? Color.adverbGold : Color.adverbInkSoft)
            }
            .buttonStyle(.plain)
            .help(playing == tag ? "Stop" : "Hear this line")
        }
    }

    static func modelTitle(_ id: String) -> String {
        AdverbSettings.voiceModels.first { $0.id == id }.map { String($0.title.split(separator: "·").first ?? "").trimmingCharacters(in: .whitespaces) } ?? id
    }
}
