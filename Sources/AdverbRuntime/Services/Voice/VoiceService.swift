//
//  VoiceService.swift
//  AdverbRuntime
//
//  WHAT: ElevenLabs' voices as Granite state: the list the pickers show, whether it is loading,
//        which voice is previewing, and which previews are already on this Mac.
//  OUT:  VoiceService+Center, Reducers/VoiceService.Set, Ops/VoiceOps
//

import Foundation
import Granite

public struct VoiceService: GraniteService {
    @Service(.online) public var center: Center
    public init() {}
}

extension VoiceService {
    public func set(_ kind: Set.Meta.Kind) {
        let meta = Set.Meta(kind: kind)
        guard !Thread.isMainThread else { center.set.send(meta); return }
        let service = self
        DispatchQueue.main.async { service.center.set.send(meta) }
    }
}
