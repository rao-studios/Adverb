//
//  MusicService.swift
//  AdverbRuntime
//
//  WHAT: The song library as Granite state: the music folder's songs, the songs added one by one,
//        the beat grids found so far and which are being analysed.
//  OUT:  MusicService+Center, Reducers/MusicService.Set, Ops/MusicOps
//

import Foundation
import Granite

public struct MusicService: GraniteService {
    @Service(.online) public var center: Center
    public init() {}
}

extension MusicService {
    public func set(_ kind: Set.Meta.Kind) {
        let meta = Set.Meta(kind: kind)
        guard !Thread.isMainThread else { center.set.send(meta); return }
        let service = self
        DispatchQueue.main.async { service.center.set.send(meta) }
    }
}
