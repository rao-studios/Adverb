//
//  GenerationService.Set.swift
//  AdverbAgents
//

import Foundation
import Granite

extension GenerationService {
    /// The one writer outside the agents' own reduce: clearing ended runs, notices. The mutation is
    /// `GenerationOps.apply`, tested as a value.
    public struct Set: GraniteReducer {
        public typealias Center = GenerationService.Center
        public init() {}

        public struct Meta: GranitePayload {
            public enum Kind: Sendable {
                case clearEnded
                case clear(key: String)
                case notice(String?)
                case problem(String?)
                case touched(UUID)
            }
            public var kind: Kind
            public init(kind: Kind) { self.kind = kind }
        }

        @Payload public var meta: Meta?

        public func reduce(state: inout Center.State) {
            guard let meta else { return }
            GenerationOps.apply(meta.kind, to: &state)
        }

        public var thread: DispatchQueue? { .main }
    }
}
