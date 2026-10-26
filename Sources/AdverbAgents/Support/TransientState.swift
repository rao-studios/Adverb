//
//  TransientState.swift
//  AdverbAgents
//
//  WHAT: A Granite state that is never persisted (Craft's): it mirrors what is true right now —
//        files on the drive, runs in flight — and is read again at launch. Codes as an empty
//        object and reads back as its defaults.
//  PIN:  Adverb's durable truth is its files (settings.json, project.json, campaign.json): a
//        service mirrors them; nothing durable lives in Granite's store.
//

import Foundation
import Granite

public protocol TransientState: GraniteState {}

extension TransientState {
    public init(from decoder: Decoder) throws { self.init() }
    public func encode(to encoder: Encoder) throws { _ = encoder.container(keyedBy: NoKeys.self) }
}

enum NoKeys: CodingKey {}
