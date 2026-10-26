//
//  SongPicker+View.swift
//  Adverb
//

import AdverbAgents
import AdverbCore
import AdverbRender
import AdverbRuntime
import SwiftUI

extension SongPicker {
    var view: some View {
        let root = AdverbRuntimeRoot.shared
        let state = music.state
        let grid = chosen.flatMap { state.grids[$0.path] }
        return VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: .hairline) {
                    Kicker(text: "Music · \(day?.date ?? "") · \(Int(duration)) s")
                    Headline(text: "Cut it *to a song.*", role: .title)
                }
                Spacer()
                Button("Music folder…") {
                    if let url = Panels.chooseFolder(title: "Music folder", prompt: "Use This Folder", message: "Adverb lists the songs in this folder. They stay where they are.",
                                                     start: FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first, canCreate: false) {
                        Task { await root.chooseMusicFolder(url) }
                    }
                }.buttonStyle(.adverbQuiet)
                Button("Add songs…") {
                    for url in Panels.chooseSongs() { Task { if let song = await root.addSong(url) { choose(song) } } }
                }.buttonStyle(.adverbQuiet)
            }
            .padding(.layer5)
            Rectangle().fill(Color.adverbBorder).frame(height: 1)
            HStack(spacing: 0) {
                library(state).frame(width: 260)
                Rectangle().fill(Color.adverbBorder).frame(width: 1)
                Group {
                    if let chosen {
                        if let grid { beatmap(chosen, grid) }
                        else if state.analyzing.contains(chosen.path) {
                            VStack(spacing: .layer2) { ProgressView().controlSize(.small); Text("Finding the beat…").adverbType(.caption).foregroundStyle(Color.adverbInkDim) }
                        } else {
                            Text(state.problem ?? "").adverbType(.caption).foregroundStyle(Color.adverbError)
                        }
                    } else {
                        EmptyState(title: "Choose *a song.*", message: "Adverb finds its beats, then moves each scene of the asset onto a downbeat and lays the song under it.", mark: false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(Color.adverbBorder).frame(height: 1)
            HStack(spacing: .layer2) {
                if day?.asset?.music != nil {
                    Text("Applying replaces this day's current cut; the silent original stays kept.").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                }
                Spacer()
                Button("Cancel") { SongPreview.shared.stop(); selection.sheet = nil }.buttonStyle(.adverbQuiet).keyboardShortcut(.cancelAction)
                Button("Cut \(Int(duration)) s to this song") { apply() }
                    .buttonStyle(.adverbGold).keyboardShortcut(.defaultAction).disabled(chosen == nil || grid == nil)
            }
            .padding(.layer4)
        }
        .frame(width: 940, height: 640)
        .background(Color.adverbPage)
        .onReceive(musicChanged) { _ in tick &+= 1 }
        .task {
            if let folder = root.settings.musicFolder, state.songs.isEmpty { await root.scanMusic(URL(fileURLWithPath: folder, isDirectory: true)) }
            #if DEBUG
            if let i = CommandLine.arguments.firstIndex(of: "--adverb-song"), CommandLine.arguments.count > i + 1,
               let song = await root.addSong(URL(fileURLWithPath: CommandLine.arguments[i + 1])) { choose(song) }
            #endif
            if chosen == nil, let current = day?.asset?.music, let song = music.state.songs.first(where: { $0.path == current.songPath }) {
                choose(song); inPoint = current.inPoint; octave = current.octave; nudge = current.phaseNudge; mode = current.mode
                gainDB = current.gainDB; fadeOut = current.fadeOut
            }
        }
        .onDisappear { SongPreview.shared.stop() }
    }

    @ViewBuilder private func library(_ state: MusicService.Center.State) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .layer1) {
                if state.scanning { ProgressView().controlSize(.small).padding(.layer3) }
                if state.songs.isEmpty, !state.scanning {
                    Text("No songs yet. Choose a music folder or add songs.").adverbType(.caption).foregroundStyle(Color.adverbInkDim).padding(.layer3)
                }
                ForEach(state.songs) { song in
                    Button { choose(song) } label: {
                        RowCard(selected: chosen?.path == song.path) {
                            VStack(alignment: .leading, spacing: .hairline) {
                                Text(song.title).adverbType(.labelStrong).lineLimit(1)
                                HStack(spacing: .layer1) {
                                    Text(song.artist ?? song.url.pathExtension.uppercased()).lineLimit(1)
                                    Spacer()
                                    if let grid = state.grids[song.path] { Text(String(format: "%.0f BPM", grid.bpm)) }
                                    else if state.analyzing.contains(song.path) { ProgressView().controlSize(.mini) }
                                    Text(Self.time(song.duration))
                                }
                                .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.layer2)
        }
        .background(Color.adverbSidebar)
    }

    @ViewBuilder private func beatmap(_ song: Song, _ grid: BeatGrid) -> some View {
        let adjusted = grid.adjusted(octave: octave, phaseNudge: nudge)
        VStack(alignment: .leading, spacing: .layer4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: .hairline) {
                    Text(song.title).adverbType(.title)
                    Text(song.artist ?? "").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                }
                Spacer()
                AdverbStat(value: String(format: "%.1f", adjusted.bpm), label: "BPM")
                AdverbStat(value: String(format: "%.0f%%", grid.confidence * 100), label: "Confidence")
                AdverbStat(value: Self.time(inPoint), label: "Starts at")
            }
            if grid.nominal || grid.confidence < 0.3 {
                Label("The beat in this song is faint: Adverb laid a steady grid from where it comes up. Check it by ear.", systemImage: "waveform.badge.exclamationmark")
                    .adverbType(.caption).foregroundStyle(Color.adverbWarning)
            }
            BeatTimeline(grid: adjusted, duration: duration, inPoint: $inPoint)
                .frame(height: 120)
            BeatWindow(grid: adjusted.window(inPoint: inPoint, duration: duration), duration: duration)
                .frame(height: 46)
            HStack(spacing: .layer4) {
                VStack(alignment: .leading, spacing: .layer1) {
                    SectionLabel("Tempo")
                    Picker("", selection: $octave) { Text("½×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                VStack(alignment: .leading, spacing: .layer1) {
                    SectionLabel("Downbeat")
                    HStack(spacing: .layer1) {
                        Button { nudge -= 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(.adverbQuiet)
                        Text(nudge == 0 ? "as found" : "\(nudge > 0 ? "+" : "")\(nudge) beat").adverbType(.caption).frame(minWidth: 60)
                        Button { nudge += 1 } label: { Image(systemName: "chevron.right") }.buttonStyle(.adverbQuiet)
                    }
                }
                VStack(alignment: .leading, spacing: .layer1) {
                    SectionLabel("Meet the beat by")
                    Picker("", selection: $mode) { ForEach(BeatmapMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                        .labelsHidden().fixedSize()
                }
                Spacer()
            }
            HStack(spacing: .layer4) {
                VStack(alignment: .leading, spacing: .layer1) {
                    SectionLabel(String(format: "Level %+.0f dB", gainDB))
                    Slider(value: $gainDB, in: -18...0, step: 1).frame(width: 160)
                }
                VStack(alignment: .leading, spacing: .layer1) {
                    SectionLabel(String(format: "Fade out %.1f s", fadeOut))
                    Slider(value: $fadeOut, in: 0.4...3, step: 0.1).frame(width: 160)
                }
                Spacer()
                Button(previewing ? "Stop" : "Preview \(Int(duration)) s") {
                    if previewing { SongPreview.shared.stop(); previewing = false }
                    else {
                        SongPreview.shared.play(song.url, from: inPoint, for: duration, fadeOut: fadeOut, gainDB: gainDB)
                        previewing = true
                        Task { try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)); previewing = false }
                    }
                }
                .buttonStyle(.adverb)
            }
            Text(mode == .warp ? "Each scene start moves to the nearest downbeat (at most 15% of a scene), the end card lands on the last downbeat before the close, and the coin and texture tap with the beat. No call to Claude."
                               : "Claude rewrites only the page's timing against the beat list; Adverb checks that nothing else changed, and warps instead if it did.")
                .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
        }
        .padding(.layer5)
    }

    private func choose(_ song: Song) {
        chosen = song
        SongPreview.shared.stop(); previewing = false
        Task {
            if let grid = await AdverbRuntimeRoot.shared.analyze(song), chosen?.path == song.path {
                inPoint = grid.suggestedInPoint(for: duration)
            }
        }
    }

    private func apply() {
        guard let song = chosen else { return }
        SongPreview.shared.stop()
        AdverbRuntimeRoot.shared.beatmap(slug, campaignID, day: dayIndex,
                                         request: RetimeRequest(song: song.url, title: song.title, artist: song.artist, inPoint: inPoint, octave: octave,
                                                                phaseNudge: nudge, gainDB: gainDB, fadeOut: fadeOut, mode: mode))
        selection.sheet = nil
    }

    static func time(_ s: Double) -> String { String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60)) }
}
