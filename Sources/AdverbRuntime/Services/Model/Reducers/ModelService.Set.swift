//
//  ModelService.Set.swift
//  AdverbRuntime
//

import AdverbCore
import Foundation
import Granite

extension ModelService {
    public struct Set: GraniteReducer {
        public typealias Center = ModelService.Center
        public init() {}

        public struct Meta: GranitePayload {
            public enum Kind: Sendable {
                case scanned(installed: Swift.Set<String>, sizes: [String: Int64], copies: [String: [ModelCopy]])
                /// Nil: the download ended.
                case downloading(String, Double?)
                case problem(String, String?)
                case loaded(Swift.Set<String>)
            }
            public var kind: Kind
            public init(kind: Kind) { self.kind = kind }
        }

        @Payload public var meta: Meta?

        public func reduce(state: inout Center.State) {
            guard let meta else { return }
            ModelOps.apply(meta.kind, to: &state)
        }

        public var thread: DispatchQueue? { .main }
    }
}
