//
//  MusicService.Set.swift
//  AdverbRuntime
//

import AdverbCore
import AdverbRender
import Foundation
import Granite

extension MusicService {
    public struct Set: GraniteReducer {
        public typealias Center = MusicService.Center
        public init() {}

        public struct Meta: GranitePayload {
            public enum Kind: Sendable {
                case scanning(folder: String?)
                case songs([Song])
                case added(Song)
                case analyzing(String)
                case grid(path: String, BeatGrid)
                case failed(path: String, String)
            }
            public var kind: Kind
            public init(kind: Kind) { self.kind = kind }
        }

        @Payload public var meta: Meta?

        public func reduce(state: inout Center.State) {
            guard let meta else { return }
            MusicOps.apply(meta.kind, to: &state)
        }

        public var thread: DispatchQueue? { .main }
    }
}
