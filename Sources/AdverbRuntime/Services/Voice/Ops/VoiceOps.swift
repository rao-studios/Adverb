//
//  VoiceOps.swift
//  AdverbRuntime
//

import Foundation

public enum VoiceOps {
    public static func apply(_ kind: VoiceService.Set.Meta.Kind, to state: inout VoiceService.Center.State) {
        switch kind {
        case .loading: state.loading = true; state.problem = nil
        case .voices(let voices, let at):
            state.voices = voices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            state.loadedAt = at
            state.loading = false
        case .failed(let message): state.loading = false; state.problem = message
        case .previewing(let id): state.previewing = id
        case .cached(let id): state.cached.insert(id)
        case .cachedAll(let ids): state.cached = ids
        }
    }
}
