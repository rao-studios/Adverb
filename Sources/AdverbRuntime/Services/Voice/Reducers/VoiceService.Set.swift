//
//  VoiceService.Set.swift
//  AdverbRuntime
//

import AdverbCore
import Foundation
import Granite

extension VoiceService {
    public struct Set: GraniteReducer {
        public typealias Center = VoiceService.Center
        public init() {}

        public struct Meta: GranitePayload {
            public enum Kind: Sendable {
                case packs([SpeechPackInfo])
                case failed(String?)
                case previewing(String?)
                case preparing(String?)
                case cached(String)
                case cachedAll(Swift.Set<String>)
            }
            public var kind: Kind
            public init(kind: Kind) { self.kind = kind }
        }

        @Payload public var meta: Meta?

        public func reduce(state: inout Center.State) {
            guard let meta else { return }
            VoiceOps.apply(meta.kind, to: &state)
        }

        public var thread: DispatchQueue? { .main }
    }
}
