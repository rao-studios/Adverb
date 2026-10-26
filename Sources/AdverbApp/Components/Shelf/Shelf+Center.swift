//
//  Shelf+Center.swift
//  Adverb
//

import Granite

extension Shelf {
    struct Center: GraniteCenter {
        struct State: GraniteState {}
        @Store var state: State
    }
}
