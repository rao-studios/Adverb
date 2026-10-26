//
//  RunProgress.swift
//  AdverbAgents
//
//  WHAT: One run as the generation panel shows it: which campaign and day, the step, the progress,
//        the latest thinking, the tokens so far, the last few log lines, and how it ended.
//

import AdverbCore
import Foundation

public enum RunPhase: String, Sendable, Equatable { case running, finished, failed, cancelled }

public struct RunProgress: Sendable, Equatable, Identifiable {
    public var key: String
    public var kind: String
    public var campaignID: UUID?
    public var dayIndex: Int?
    public var step: String = "Starting"
    public var progress: Double = 0
    public var activity: String = ""
    public var usage = TokenUsage()
    public var log: [String] = []
    public var phase: RunPhase = .running
    public var message: String?
    public var startedAt = Date()
    public var endedAt: Date?

    public var id: String { key }

    public init(key: String, kind: String, campaignID: UUID?, dayIndex: Int?) {
        self.key = key; self.kind = kind; self.campaignID = campaignID; self.dayIndex = dayIndex
    }
}

/// Run keys: "plan/<campaign>", "<campaign>/<day>", "beat/<campaign>/<day>".
public enum RunKey {
    public static func plan(_ campaign: UUID) -> String { "plan/\(campaign.uuidString)" }
    public static func build(_ campaign: UUID, _ day: Int) -> String { "\(campaign.uuidString)/\(day)" }
    public static func beat(_ campaign: UUID, _ day: Int) -> String { "beat/\(campaign.uuidString)/\(day)" }

    public static func parse(_ key: String) -> (kind: String, campaign: UUID?, day: Int?) {
        let parts = key.split(separator: "/").map(String.init)
        switch parts.first {
        case "plan": return ("Plan", parts.count > 1 ? UUID(uuidString: parts[1]) : nil, nil)
        case "beat": return ("Beatmap", parts.count > 1 ? UUID(uuidString: parts[1]) : nil, parts.count > 2 ? Int(parts[2]) : nil)
        default: return ("Build", UUID(uuidString: parts.first ?? ""), parts.count > 1 ? Int(parts[1]) : nil)
        }
    }
}
