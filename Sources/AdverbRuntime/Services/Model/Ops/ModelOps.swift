//
//  ModelOps.swift
//  AdverbRuntime
//

import Foundation

public enum ModelOps {
    public static func apply(_ kind: ModelService.Set.Meta.Kind, to state: inout ModelService.Center.State) {
        switch kind {
        case .scanned(let installed, let sizes):
            state.installed = installed; state.sizes = sizes; state.scanned = true
        case .downloading(let id, let fraction):
            if let fraction { state.downloading[id] = fraction; state.problems[id] = nil } else { state.downloading[id] = nil }
        case .problem(let id, let text):
            state.problems[id] = text
            if text != nil { state.downloading[id] = nil }
        case .loaded(let ids): state.loaded = ids
        }
    }
}
