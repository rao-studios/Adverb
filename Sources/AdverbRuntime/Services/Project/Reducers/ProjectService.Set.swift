//
//  ProjectService.Set.swift
//  AdverbRuntime
//

import AdverbCore
import Foundation
import Granite

extension ProjectService {
    public struct Set: GraniteReducer {
        public typealias Center = ProjectService.Center
        public init() {}

        public struct Meta: GranitePayload {
            public enum Kind: Sendable {
                case loaded([Project])
                case saved(Project)
                case removed(slug: String)
            }
            public var kind: Kind
            public init(kind: Kind) { self.kind = kind }
        }

        @Payload public var meta: Meta?

        public func reduce(state: inout Center.State) {
            guard let meta else { return }
            ProjectOps.apply(meta.kind, to: &state)
        }

        public var thread: DispatchQueue? { .main }
    }
}
