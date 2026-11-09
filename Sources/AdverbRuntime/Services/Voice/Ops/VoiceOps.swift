//
//  VoiceOps.swift
//  AdverbRuntime
//

import Foundation

public enum VoiceOps {
    public static func apply(_ kind: VoiceService.Set.Meta.Kind, to state: inout VoiceService.Center.State) {
        switch kind {
        case .packs(let packs): state.packs = packs; state.problem = nil
        case .failed(let message): state.problem = message
        case .previewing(let tag): state.previewing = tag
        case .preparing(let tag): state.preparing = tag
        case .cached(let tag): state.cached.insert(tag)
        case .cachedAll(let tags): state.cached = tags
        }
    }
}
