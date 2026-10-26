//
//  CampaignService.Set.swift
//  AdverbRuntime
//

import AdverbCore
import Foundation
import Granite

extension CampaignService {
    public struct Set: GraniteReducer {
        public typealias Center = CampaignService.Center
        public init() {}

        public struct Meta: GranitePayload {
            public enum Kind: Sendable {
                case loaded(slug: String, [Campaign])
                case updated(slug: String, Campaign)
                case removed(slug: String, UUID)
                case forgetProject(String)
            }
            public var kind: Kind
            public init(kind: Kind) { self.kind = kind }
        }

        @Payload public var meta: Meta?

        public func reduce(state: inout Center.State) {
            guard let meta else { return }
            CampaignOps.apply(meta.kind, to: &state)
        }

        public var thread: DispatchQueue? { .main }
    }
}
