//
//  CaptionSample.swift
//  AdverbCore
//
//  WHAT: What the renderer saw on screen at one instant: each visible text block, its kind and
//        where it sits. A render records one every 0.1 s; CueTracker folds them into cues.
//

import Foundation

public struct CaptionItem: Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var text: String
    /// headline, kicker, chip, code, body, end
    public var kind: String
    public var x: Int
    public var y: Int

    public init(id: String, text: String, kind: String, x: Int, y: Int) {
        self.id = id; self.text = text; self.kind = kind; self.x = x; self.y = y
    }
}

public struct CaptionSample: Codable, Sendable, Equatable {
    /// Video time, seconds.
    public var t: Double
    public var items: [CaptionItem]

    public init(t: Double, items: [CaptionItem]) { self.t = t; self.items = items }
}
