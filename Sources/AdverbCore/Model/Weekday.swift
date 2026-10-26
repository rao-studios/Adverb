//
//  Weekday.swift
//  AdverbCore
//
//  WHAT: A day of the week, numbered as Foundation's Calendar numbers them (Sunday = 1).
//

import Foundation

public enum Weekday: Int, Codable, Sendable, CaseIterable, Hashable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }
    public var short: String { ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][rawValue - 1] }
    public static let all: [Weekday] = allCases
}
