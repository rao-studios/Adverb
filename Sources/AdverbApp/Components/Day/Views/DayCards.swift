//
//  DayCards.swift
//  Adverb
//
//  WHAT: The day pane's cards: the run working on it, the plan before it is built, when to post
//        and why, the post, its status, accessibility, music, notes and files.
//

import AdverbAgents
import AdverbCore
import AdverbRuntime
import SwiftUI

struct RunCard: View {
    let run: RunProgress

    var body: some View {
        AdverbCard(gold: true) {
            VStack(alignment: .leading, spacing: .layer2) {
                HStack {
                    StatusDot(color: .adverbGold, pulsing: true)
                    Text(run.step).adverbType(.labelStrong)
                    Spacer()
                    Button("Stop") { AdverbRuntimeRoot.shared.cancelRun(run.key) }.buttonStyle(.adverbQuiet).controlSize(.small)
                }
                AdverbMeter(fraction: run.progress)
                if !run.activity.isEmpty {
                    Text(String(run.activity.suffix(320))).adverbType(.readingSmall).foregroundStyle(Color.adverbInkDim).lineLimit(5)
                }
            }
        }
    }
}

struct ScenesCard: View {
    let day: CampaignDay
    let build: () -> Void

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("Planned · \(day.topic.duration) s · \(day.topic.kicker)")
                ForEach(Array(day.topic.scenes.enumerated()), id: \.offset) { _, scene in
                    HStack(alignment: .firstTextBaseline, spacing: .layer2) {
                        Text(String(format: "%.1f s", scene.at)).adverbType(.codeSmall).foregroundStyle(Color.adverbInkMuted).frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: .hairline) {
                            Text(scene.recipe).adverbType(.captionStrong)
                            Text(scene.what).adverbType(.readingSmall).foregroundStyle(Color.adverbInkDim)
                        }
                    }
                }
                Button("Build this day", action: build).buttonStyle(.adverb)
            }
        }
    }
}

struct WhenCard: View {
    let day: CampaignDay
    let zone: String

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("When and where")
                HStack(spacing: .layer2) {
                    Text(day.postTimeLocal).adverbType(.figure)
                    Text(zone).adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                    Spacer()
                }
                FlowLayout { ForEach(day.targets, id: \.platform) { t in AdverbChip(label: "\(t.platform.shortTitle) · \(t.orientation.rawValue)", systemImage: t.platform.symbol, isOn: t.postedAt != nil) } }
                Text(day.timeReason).adverbType(.readingSmall).foregroundStyle(Color.adverbInkSoft)
            }
        }
    }
}

struct PostCard: View {
    let day: CampaignDay
    let save: (CampaignDay) -> Void
    @State private var caption = ""
    @State private var tags = ""
    @State private var editing = false

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                HStack {
                    SectionLabel("The post")
                    Spacer()
                    Button(editing ? "Done" : "Edit") {
                        if editing {
                            var d = day
                            d.caption = caption
                            d.hashtags = tags.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }.filter { !$0.isEmpty }
                            save(d)
                        }
                        editing.toggle()
                    }.buttonStyle(.adverbLink)
                    Button("Copy") { Panels.copy(day.postText) }.buttonStyle(.adverbQuiet).controlSize(.small).help("Caption and hashtags")
                }
                if editing {
                    AdverbTextArea(text: $caption, minHeight: 110)
                    AdverbTextField(placeholder: "hashtags, space separated", text: $tags)
                } else {
                    Text(day.caption).adverbType(.reading).textSelection(.enabled)
                    Text(day.hashtags.map { "#\($0)" }.joined(separator: " ")).adverbType(.label).foregroundStyle(Color.adverbGoldDeep).textSelection(.enabled)
                }
                let length = PlatformLimits.length(caption: editing ? caption : day.caption, hashtags: day.hashtags)
                FlowLayout(spacing: .layer2) {
                    ForEach(day.targets, id: \.platform) { t in
                        let max = PlatformLimits.captionMax(t.platform)
                        Text("\(t.platform.shortTitle) \(length)/\(max)").adverbType(.codeSmall)
                            .foregroundStyle(length > max ? Color.adverbError : Color.adverbInkMuted)
                    }
                }
            }
        }
        .onAppear { caption = day.caption; tags = day.hashtags.joined(separator: " ") }
        .onChange(of: day.caption) { _, v in if !editing { caption = v } }
    }
}

struct StatusCard: View {
    let day: CampaignDay
    let set: (PostStatus, Platform?) -> Void

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                HStack {
                    SectionLabel("Status")
                    Spacer()
                    AdverbBadge(text: day.status.title, color: day.status == .posted ? .adverbGold : .adverbInkDim, filled: day.status == .posted)
                }
                ForEach(day.targets, id: \.platform) { target in
                    HStack {
                        Image(systemName: target.platform.symbol).frame(width: 16)
                        Text(target.platform.title).adverbType(.label)
                        Spacer()
                        if let posted = target.postedAt {
                            Text("Posted \(posted.formatted(date: .abbreviated, time: .shortened))").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                        } else {
                            Button("Mark posted") { set(.posted, target.platform) }.buttonStyle(.adverbQuiet).controlSize(.small)
                                .disabled(day.asset == nil)
                        }
                    }
                }
                HStack {
                    if day.status != .skipped { Button("Skip this day") { set(.skipped, nil) }.buttonStyle(.adverbLink) }
                    if day.status == .posted || day.status == .skipped { Button("Reset") { set(.planned, nil) }.buttonStyle(.adverbLink) }
                }
                Text("Posting is by hand for now: copy the post, upload the video, mark it posted.").adverbType(.fine).foregroundStyle(Color.adverbInkMuted)
            }
        }
    }
}

struct AccessibilityCard: View {
    let asset: Asset
    let paths: CampaignPaths
    let platforms: [Platform]

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                HStack {
                    SectionLabel("Accessibility")
                    Spacer()
                    let problems = asset.a11y.checks.filter { $0.level != .ok }
                    AdverbBadge(text: problems.isEmpty ? "Complete" : "\(problems.count) to check", color: problems.isEmpty ? .adverbSuccess : .adverbWarning)
                }
                HStack(alignment: .top) {
                    Text(asset.a11y.altText).adverbType(.readingSmall).textSelection(.enabled)
                    Spacer()
                    Button("Copy") { Panels.copy(asset.a11y.altText) }.buttonStyle(.adverbQuiet).controlSize(.small).help("Alt text")
                }
                FlowLayout(spacing: .layer2) {
                    ForEach(platforms, id: \.self) { p in
                        if let max = PlatformLimits.altTextMax(p) {
                            Text("\(p.shortTitle) alt \(asset.a11y.altText.count)/\(max)").adverbType(.codeSmall)
                                .foregroundStyle(asset.a11y.altText.count > max ? Color.adverbError : Color.adverbInkMuted)
                        }
                    }
                }
                ForEach(asset.a11y.checks, id: \.message) { check in
                    Label(check.message, systemImage: check.level == .ok ? "checkmark.circle" : "exclamationmark.circle")
                        .adverbType(.caption).foregroundStyle(check.level == .ok ? Color.adverbSuccess : (check.level == .warning ? Color.adverbWarning : Color.adverbError))
                }
                HStack(spacing: .layer2) {
                    ForEach(Orientation.allCases, id: \.self) { o in
                        if let files = asset.a11y.captions(o) {
                            Button("\(o.title) captions") { Panels.reveal([paths.url(files.vtt), paths.url(files.srt)]) }.buttonStyle(.adverbLink)
                                .help("\(files.cueCount) cues · WebVTT and SRT")
                        }
                    }
                    if let d = asset.a11y.descriptionsPath { Button("Descriptions") { Panels.reveal([paths.url(d)]) }.buttonStyle(.adverbLink) }
                    if let t = asset.a11y.transcriptPath { Button("Transcript") { Panels.reveal([paths.url(t)]) }.buttonStyle(.adverbLink) }
                }
            }
        }
    }
}

struct MusicCard: View {
    let asset: Asset
    let busy: Bool
    let choose: () -> Void
    let revert: () -> Void

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("Music")
                if let music = asset.music {
                    Text(music.credit).adverbType(.heading)
                    Text(String(format: "%.1f BPM · from %.1f s · %@ · %+.0f dB", music.bpm, music.inPoint, music.mode.title.lowercased(), music.gainDB))
                        .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                    HStack {
                        Button("Another song…", action: choose).buttonStyle(.adverbQuiet).disabled(busy)
                        Button("Back to the silent original", action: revert).buttonStyle(.adverbLink).disabled(busy)
                    }
                } else {
                    Text("Silent, with a quiet audio track so music can be added in an app. Cut it to a song and the scenes land on the beat.")
                        .adverbType(.readingSmall).foregroundStyle(Color.adverbInkDim)
                    Button("Cut to a song…", action: choose).buttonStyle(.adverb).disabled(busy)
                }
            }
        }
    }
}

struct NotesCard: View {
    let notes: AssetNotes
    let reviewed: Bool

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                HStack {
                    SectionLabel("About this asset")
                    Spacer()
                    if reviewed { AdverbBadge(text: "Stills reviewed", color: .adverbInkDim) }
                }
                if !notes.summary.isEmpty { Text(notes.summary).adverbType(.readingSmall) }
                list("Illustrative", notes.illustrative)
                list("Softened for accuracy", notes.softened)
                list("Sources", notes.sources)
            }
        }
    }

    @ViewBuilder private func list(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: .hairline) {
                Text(title).adverbType(.captionStrong).foregroundStyle(Color.adverbInkDim)
                ForEach(items, id: \.self) { Text("· \($0)").adverbType(.caption).foregroundStyle(Color.adverbInkDim).textSelection(.enabled) }
            }
        }
    }
}

struct FilesCard: View {
    let asset: Asset
    let paths: CampaignPaths
    let stem: String

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("Files")
                ForEach(asset.renders, id: \.orientation) { r in
                    HStack {
                        Text(URL(fileURLWithPath: r.path).lastPathComponent).adverbType(.identifier).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Reveal") { Panels.reveal([paths.url(r.path)]) }.buttonStyle(.adverbLink)
                    }
                }
                ForEach(asset.voiceOver?.languages.filter(\.isFresh) ?? [], id: \.language) { track in
                    ForEach(track.renders, id: \.orientation) { r in
                        HStack {
                            Text(URL(fileURLWithPath: r.path).lastPathComponent).adverbType(.identifier).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Reveal") { Panels.reveal([paths.url(r.path)]) }.buttonStyle(.adverbLink)
                        }
                    }
                    HStack(spacing: .layer3) {
                        Button("\(track.language.title) captions") {
                            Panels.reveal(track.captions.values.flatMap { [paths.url($0.vtt), paths.url($0.srt)] })
                        }.buttonStyle(.adverbLink)
                        if let transcript = track.transcriptPath {
                            Button("\(track.language.title) transcript") { NSWorkspace.shared.open(paths.url(transcript)) }.buttonStyle(.adverbLink)
                        }
                    }
                }
                HStack(spacing: .layer3) {
                    if let sheet = asset.sheetPath { Button("Contact sheet") { NSWorkspace.shared.open(paths.url(sheet)) }.buttonStyle(.adverbLink) }
                    Button("Page") { Panels.reveal([paths.url(asset.pagePath)]) }.buttonStyle(.adverbLink)
                    Button("Folder") { Panels.reveal([paths.url(asset.folder)]) }.buttonStyle(.adverbLink)
                    if let script = asset.voiceOver?.english.scriptPath { Button("Voice script") { Panels.reveal([paths.url(script)]) }.buttonStyle(.adverbLink) }
                }
            }
        }
    }
}
