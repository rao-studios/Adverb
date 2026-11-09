//
//  ModelService+Center.swift
//  AdverbRuntime
//

import AdverbAgents
import AdverbCore
import Foundation
import Granite

extension ModelService {
    public struct Center: GraniteCenter {
        public init() {}

        public struct State: TransientState {
            public var memoryGB = ModelCatalog.physicalMemoryGB
            /// Installed models by id (a catalog repository, or the setting's own repo or folder).
            public var installed: Swift.Set<String> = []
            /// Bytes on disk, by id.
            public var sizes: [String: Int64] = [:]
            /// Downloads under way: id → fraction done.
            public var downloading: [String: Double] = [:]
            /// The last thing that went wrong with a model, by id.
            public var problems: [String: String] = [:]
            /// Loaded in this process.
            public var loaded: Swift.Set<String> = []
            /// Read from disk at least once.
            public var scanned = false
            public init() {}

            public func isInstalled(_ id: String) -> Bool { installed.contains(id) }
            public func isDownloading(_ id: String) -> Bool { downloading[id] != nil }
            public var recommended: ModelSet { ModelCatalog.recommended(memoryGB: memoryGB) }
            public var installedSpeech: [ModelSpec] { ModelCatalog.speech.filter { installed.contains($0.id) } }
            public var totalBytes: Int64 { sizes.values.reduce(0, +) }
        }

        @Event public var set: Set.Reducer
        @Store public var state: State
    }
}
