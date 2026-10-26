//
//  Root+Center.swift
//  Adverb
//

import Granite

extension Root {
    struct Center: GraniteCenter {
        struct State: GraniteState {}
        @Store var state: State
    }
}
