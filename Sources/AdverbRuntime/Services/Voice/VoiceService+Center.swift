//
//  VoiceService+Center.swift
//  AdverbRuntime
//

import AdverbAgents
import AdverbCore
import Foundation
import Granite

extension VoiceService {
    public struct Center: GraniteCenter {
        public init() {}

        public struct State: TransientState {
            public var voices: [ElevenVoice] = []
            public var loading = false
            public var loadedAt: Date?
            /// The voice whose preview is playing, by id.
            public var previewing: String?
            /// Voices whose preview is cached on this Mac.
            public var cached: Swift.Set<String> = []
            public var problem: String?
            public init() {}

            public func voice(_ id: String?) -> ElevenVoice? { id.flatMap { i in voices.first { $0.id == i } } }
        }

        @Event public var set: Set.Reducer
        @Store public var state: State
    }
}
