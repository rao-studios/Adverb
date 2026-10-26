//
//  ConfigOps.swift
//  AdverbRuntime
//

import Foundation

public enum ConfigOps {
    public static func apply(_ kind: ConfigService.Set.Meta.Kind, to state: inout ConfigService.Center.State) {
        switch kind {
        case .settings(let s): state.settings = s
        case .key(let source, let masked): state.keySource = source; state.keyMasked = masked; state.keyChecked = nil
        case .keyChecked(let ok): state.keyChecked = ok
        case .gate(let gate): state.gate = gate
        case .toolchain(let checks): state.toolchain = checks
        case .notice(let text): state.notice = text; if text != nil { state.problem = nil }
        case .problem(let text): state.problem = text; if text != nil { state.notice = nil }
        }
    }
}
