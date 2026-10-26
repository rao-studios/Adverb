//
//  CampaignService+Center.swift
//  AdverbRuntime
//

import AdverbAgents
import AdverbCore
import Foundation
import Granite

extension CampaignService {
    public struct Center: GraniteCenter {
        public init() {}

        public struct State: TransientState {
            /// Project slug → its campaigns, newest first.
            public var byProject: [String: [Campaign]] = [:]
            public init() {}

            public func campaigns(_ slug: String?) -> [Campaign] { slug.flatMap { byProject[$0] } ?? [] }

            public func campaign(_ id: UUID?) -> Campaign? {
                guard let id else { return nil }
                for list in byProject.values { if let c = list.first(where: { $0.id == id }) { return c } }
                return nil
            }

            public func slug(of id: UUID) -> String? { byProject.first { $0.value.contains { $0.id == id } }?.key }
        }

        @Event public var set: Set.Reducer
        @Store public var state: State
    }
}
