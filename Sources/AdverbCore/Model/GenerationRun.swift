//
//  GenerationRun.swift
//  AdverbCore
//
//  WHAT: One run of the generator, as its log records it: what it did, step by step, what it cost,
//        and how it ended. Written beside the campaign (logs/) when the run ends.
//

import Foundation

public enum RunKind: Codable, Sendable, Equatable, Hashable {
    case plan
    case build(days: [Int])
    case beatmap(day: Int)
    /// A day's English voice-over: scripted, recorded and mixed.
    case voice(day: Int)
    /// A day's narration in other languages, after its English was confirmed.
    case languages(day: Int, [Language])

    public var title: String {
        switch self {
        case .plan: "Plan"
        case .build(let days): days.count == 1 ? "Build" : "Build \(days.count) days"
        case .beatmap: "Beatmap"
        case .voice: "Voice-over"
        case .languages(_, let languages): languages.count == 1 ? languages[0].title : "\(languages.count) languages"
        }
    }

    public var slug: String {
        switch self {
        case .plan: "plan"
        case .build: "build"
        case .beatmap: "beatmap"
        case .voice: "voice"
        case .languages: "languages"
        }
    }
}

public enum RunOutcome: Codable, Sendable, Equatable, Hashable {
    case running, succeeded, failed(String), cancelled
}

public struct StepRecord: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var dayIndex: Int?
    public var startedAt: Date
    public var finishedAt: Date?
    public var message: String?

    public init(name: String, dayIndex: Int? = nil, startedAt: Date = Date(), finishedAt: Date? = nil, message: String? = nil) {
        self.name = name; self.dayIndex = dayIndex; self.startedAt = startedAt; self.finishedAt = finishedAt; self.message = message
    }
}

public struct TokenUsage: Codable, Sendable, Equatable, Hashable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input; self.output = output; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite
    }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, output: a.output + b.output, cacheRead: a.cacheRead + b.cacheRead, cacheWrite: a.cacheWrite + b.cacheWrite)
    }

    public var isEmpty: Bool { input + output + cacheRead + cacheWrite == 0 }

    /// Share of prompt tokens served from cache.
    public var cacheHitRate: Double {
        let prompt = input + cacheRead + cacheWrite
        return prompt == 0 ? 0 : Double(cacheRead) / Double(prompt)
    }

    /// An estimate in US dollars at the model's list price (per million tokens): cache writes at
    /// 1.25× input for the 5-minute TTL and 2× for the hour, reads at 0.1×.
    public func estimatedUSD(model: String, cacheTTLHour: Bool = true) -> Double {
        let (inPrice, outPrice) = Self.prices(model)
        let writeFactor = cacheTTLHour ? 2.0 : 1.25
        let dollars = Double(input) * inPrice + Double(output) * outPrice
            + Double(cacheWrite) * inPrice * writeFactor + Double(cacheRead) * inPrice * 0.1
        return dollars / 1_000_000
    }

    static func prices(_ model: String) -> (Double, Double) {
        switch model {
        case "claude-fable-5-1", "claude-fable-5": (10, 50)
        case "claude-opus-5-5": (4, 20)
        case "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7": (5, 25)
        case "claude-sonnet-5-5", "claude-sonnet-5": (2, 10)
        case "claude-haiku-5-5": (0.10, 0.50)
        default: (4, 20)
        }
    }
}

public struct GenerationRun: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var campaignID: UUID
    public var kind: RunKind
    public var model: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var outcome: RunOutcome
    public var steps: [StepRecord]
    public var usage: TokenUsage
    /// What the run spent at ElevenLabs, when it spoke.
    public var voice: VoiceUsage?
    /// Relative to the campaign folder.
    public var logPath: String

    public init(id: UUID = UUID(), campaignID: UUID, kind: RunKind, model: String, startedAt: Date = Date(), logPath: String) {
        self.id = id; self.campaignID = campaignID; self.kind = kind; self.model = model; self.startedAt = startedAt
        self.finishedAt = nil; self.outcome = .running; self.steps = []; self.usage = TokenUsage(); self.logPath = logPath
    }
}
