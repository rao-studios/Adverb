//
//  ConfigService+Center.swift
//  AdverbRuntime
//

import AdverbAgents
import AdverbCore
import Foundation
import Granite

/// What stands between the person and their projects, in order.
public enum Gate: Sendable, Equatable {
    case loading
    case needsKey
    case needsWorkdir
    case driveNotMounted(String)
    case workdirMissing(String)
    case noProjects
    case ready

    public var isReady: Bool { self == .ready || self == .noProjects }
}

public struct ToolCheck: Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable { case ok, missing, optional }
    public var id: String
    public var title: String
    public var status: Status
    public var detail: String
    public var fix: String?

    public init(id: String, title: String, status: Status, detail: String, fix: String? = nil) {
        self.id = id; self.title = title; self.status = status; self.detail = detail; self.fix = fix
    }
}

extension ConfigService {
    public struct Center: GraniteCenter {
        public init() {}

        public struct State: TransientState {
            public var settings = AdverbSettings()
            public var keySource: KeySource?
            public var keyMasked: String?
            public var keyChecked: Bool?
            /// The ElevenLabs key: optional, never a gate.
            public var voiceKeySource: KeySource?
            public var voiceKeyMasked: String?
            public var voiceKeyChecked: Bool?
            public var voiceQuota: VoiceQuota?
            public var gate: Gate = .loading
            public var toolchain: [ToolCheck] = []
            public var notice: String?
            public var problem: String?
            public init() {}

            public var hasKey: Bool { keySource != nil }
            public var hasVoiceKey: Bool { voiceKeySource != nil }
        }

        @Event public var set: Set.Reducer
        @Store public var state: State
    }
}
