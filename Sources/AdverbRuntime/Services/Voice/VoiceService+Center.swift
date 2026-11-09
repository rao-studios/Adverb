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
            /// The packs installed on this Mac, with their voices.
            public var packs: [SpeechPackInfo] = []
            /// What is playing: a voice's preview ("<pack>/<voice>") or a clip's tag.
            public var previewing: String?
            /// A preview being spoken for the first time.
            public var preparing: String?
            /// Previews already spoken and kept ("<pack>/<voice>").
            public var cached: Swift.Set<String> = []
            public var problem: String?
            public init() {}

            public var voices: [SpeechVoice] { packs.flatMap(\.voices) }
            public func voice(_ id: String?, pack: String? = nil) -> SpeechVoice? {
                guard let id else { return nil }
                return voices.first { $0.id == id && (pack == nil || $0.packID == pack) } ?? voices.first { $0.id == id }
            }
            public func pack(_ id: String) -> SpeechPackInfo? { packs.first { $0.id == id } }
            public static func tag(_ voice: SpeechVoice) -> String { "\(voice.packID)/\(voice.id)" }
        }

        @Event public var set: Set.Reducer
        @Store public var state: State
    }
}
