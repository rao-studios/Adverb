//
//  ModelService.swift
//  AdverbRuntime
//
//  WHAT: The models on this Mac as Granite state: which of the catalog's are installed (and how
//        big), which are downloading and how far, what went wrong, which are loaded. Onboarding,
//        Settings › Models and Settings › Voice read it; the root's model actions write it.
//  OUT:  ModelService+Center, Reducers/ModelService.Set, Ops/ModelOps
//

import Foundation
import Granite

public struct ModelService: GraniteService {
    @Service(.online) public var center: Center
    public init() {}
}

extension ModelService {
    public func set(_ kind: Set.Meta.Kind) {
        let meta = Set.Meta(kind: kind)
        guard !Thread.isMainThread else { center.set.send(meta); return }
        let service = self
        DispatchQueue.main.async { service.center.set.send(meta) }
    }
}
