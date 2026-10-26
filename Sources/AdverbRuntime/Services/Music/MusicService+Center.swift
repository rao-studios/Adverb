//
//  MusicService+Center.swift
//  AdverbRuntime
//

import AdverbAgents
import AdverbCore
import AdverbRender
import Foundation
import Granite

extension MusicService {
    public struct Center: GraniteCenter {
        public init() {}

        public struct State: TransientState {
            public var folder: String?
            public var songs: [Song] = []
            public var grids: [String: BeatGrid] = [:]
            public var analyzing: Swift.Set<String> = []
            public var scanning = false
            public var problem: String?
            public init() {}
        }

        @Event public var set: Set.Reducer
        @Store public var state: State
    }
}
