//
//  ProjectService.swift
//  AdverbRuntime
//
//  WHAT: The projects in the working directory, as Granite state, in the index's order.
//  OUT:  ProjectService+Center, Reducers/ProjectService.Set, Ops/ProjectOps
//  PIN:  A mirror of <workdir>/Adverb/*/project.json; the root writes through ProjectStore and
//        reads back here.
//

import Foundation
import Granite

public struct ProjectService: GraniteService {
    @Service(.online) public var center: Center
    public init() {}
}

extension ProjectService {
    public func set(_ kind: Set.Meta.Kind) {
        let meta = Set.Meta(kind: kind)
        guard !Thread.isMainThread else { center.set.send(meta); return }
        let service = self
        DispatchQueue.main.async { service.center.set.send(meta) }
    }
}
