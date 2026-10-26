//
//  ProjectService+Center.swift
//  AdverbRuntime
//

import AdverbAgents
import AdverbCore
import Foundation
import Granite

extension ProjectService {
    public struct Center: GraniteCenter {
        public init() {}

        public struct State: TransientState {
            public var projects: [Project] = []
            public var loaded = false
            public init() {}

            public func project(_ slug: String?) -> Project? { slug.flatMap { s in projects.first { $0.slug == s } } }
        }

        @Event public var set: Set.Reducer
        @Store public var state: State
    }
}
