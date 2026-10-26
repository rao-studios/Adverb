//
//  Onboarding+Center.swift
//  Adverb
//

import Granite

extension Onboarding {
    struct Center: GraniteCenter {
        struct State: GraniteState {}
        @Store var state: State
    }
}
