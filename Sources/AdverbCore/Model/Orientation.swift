//
//  Orientation.swift
//  AdverbCore
//
//  WHAT: The two shapes every asset ships in (rao-motion-assets: portrait 1080×1920, landscape
//        1920×1080), and the letter the kit's `?o=` takes.
//

import Foundation

public enum Orientation: String, Codable, Sendable, CaseIterable, Hashable {
    case portrait, landscape

    /// `?o=P` / `?o=L`, and the stills' file-name letter.
    public var letter: String { self == .portrait ? "P" : "L" }
    public var width: Int { self == .portrait ? 1080 : 1920 }
    public var height: Int { self == .portrait ? 1920 : 1080 }
    public var title: String { self == .portrait ? "Portrait" : "Landscape" }
}
