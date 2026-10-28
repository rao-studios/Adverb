//
//  ConfigService.Set.swift
//  AdverbRuntime
//

import AdverbCore
import Foundation
import Granite

extension ConfigService {
    public struct Set: GraniteReducer {
        public typealias Center = ConfigService.Center
        public init() {}

        public struct Meta: GranitePayload {
            public enum Kind: Sendable {
                case settings(AdverbSettings)
                case key(source: KeySource?, masked: String?)
                case keyChecked(Bool?)
                case voiceKey(source: KeySource?, masked: String?)
                case voiceKeyChecked(Bool?)
                case voiceQuota(VoiceQuota?)
                case gate(Gate)
                case toolchain([ToolCheck])
                case notice(String?)
                case problem(String?)
            }
            public var kind: Kind
            public init(kind: Kind) { self.kind = kind }
        }

        @Payload public var meta: Meta?

        public func reduce(state: inout Center.State) {
            guard let meta else { return }
            ConfigOps.apply(meta.kind, to: &state)
        }

        public var thread: DispatchQueue? { .main }
    }
}
