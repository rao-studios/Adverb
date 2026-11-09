//
//  VoiceService.swift
//  AdverbRuntime
//
//  WHAT: The voices on this Mac as Granite state: the packs and their voices the pickers show,
//        which voice is being previewed (or spoken for its preview), and which previews are made.
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
