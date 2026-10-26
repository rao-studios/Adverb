//
//  MusicOps.swift
//  AdverbRuntime
//

import Foundation

public enum MusicOps {
    public static func apply(_ kind: MusicService.Set.Meta.Kind, to state: inout MusicService.Center.State) {
        switch kind {
        case .scanning(let folder): state.scanning = true; state.folder = folder
        case .songs(let songs):
            let added = state.songs.filter { s in !songs.contains { $0.path == s.path } && !(state.folder.map { s.path.hasPrefix($0) } ?? false) }
            state.songs = (songs + added).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            state.scanning = false
        case .added(let song):
            if !state.songs.contains(where: { $0.path == song.path }) { state.songs.insert(song, at: 0) }
        case .analyzing(let path): state.analyzing.insert(path); state.problem = nil
        case .grid(let path, let grid): state.grids[path] = grid; state.analyzing.remove(path)
        case .failed(let path, let message): state.analyzing.remove(path); state.problem = message
        }
    }
}
