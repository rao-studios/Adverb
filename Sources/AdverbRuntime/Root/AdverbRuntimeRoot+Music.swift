//
//  AdverbRuntimeRoot+Music.swift
//  AdverbRuntime
//
//  WHAT: The song library and re-cutting a day to a song: choose the music folder, add a song,
//        find its beats, beatmap a day, revert a day to its silent original.
//

import AdverbAgents
import AdverbCore
import AdverbRender
import Foundation

extension AdverbRuntimeRoot {
    public func chooseMusicFolder(_ url: URL) async {
        update { $0.musicFolder = url.standardizedFileURL.path }
        await scanMusic(url)
    }

    public func scanMusic(_ folder: URL) async {
        music.set(.scanning(folder: folder.path))
        let songs = await SongLibrary.scan(folder)
        music.set(.songs(songs))
    }

    public func addSong(_ url: URL) async -> Song? {
        guard let song = await SongLibrary.song(url) else {
            music.set(.failed(path: url.path, "That file has no audio AVFoundation can read."))
            return nil
        }
        music.set(.added(song))
        return song
    }

    @discardableResult
    public func analyze(_ song: Song) async -> BeatGrid? {
        if let grid = music.state.grids[song.path] { return grid }
        music.set(.analyzing(song.path))
        do {
            let grid = try await BeatAnalyzer.shared.analyze(song.url)
            music.set(.grid(path: song.path, grid))
            return grid
        } catch {
            music.set(.failed(path: song.path, "\(error)"))
            return nil
        }
    }

    public func beatmap(_ slug: String, _ id: UUID, day: Int, request: RetimeRequest) {
        let key = RunKey.beat(id, day)
        watch(generation.center.$retimer.events(key: key), slug: slug, id: id)
        generation.center.retimer.send(Retimer.Input(projectSlug: slug, campaignID: id, dayIndex: day, request: request))
    }

    public func revert(_ slug: String, _ id: UUID, day: Int) async {
        guard let paths = paths(slug, id), let campaign = campaigns.state.campaign(id), let d = campaign.day(day), let asset = d.asset else { return }
        do {
            let reverted = try AssetFinisher.revert(asset, paths: paths, assetPaths: paths.asset(d.stem))
            let updated = try await CampaignLedger.shared.updateDay(paths, index: day) { $0.asset = reverted }
            campaigns.set(.updated(slug: slug, updated))
            config.set(.notice("Day \(d.date) is back to its silent original."))
        } catch {
            config.set(.problem("\(error)"))
        }
    }

    public func checkToolchain() async {
        let checks = await Task.detached { Toolchain.check() }.value
        config.set(.toolchain(checks.map { ToolCheck(id: $0.id, title: $0.title, status: $0.ok == true ? .ok : ($0.id == "ffmpeg" ? .optional : .missing),
                                                      detail: $0.detail, fix: $0.fix) }))
    }
}
