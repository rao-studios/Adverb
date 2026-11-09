//
//  GenerationRun.swift
//  AdverbCore
//
//  WHAT: One run of the generator, as its log records it: what it did, step by step, how much the
//        model read and wrote and how long it took, and how it ended. Written beside the campaign
//        (logs/) when the run ends.
//

import Foundation

public enum RunKind: Codable, Sendable, Equatable, Hashable {
    case plan
    /// The ElevenLabs-era build of a day, page to video in one run (older logs).
    case build(days: [Int])
    /// A day written: page, voice-over, stills, review, contact sheet.
    case draft(day: Int)
    /// A day rendered from its sheet: videos, captions, the final sheet.
    case render(day: Int)
    case beatmap(day: Int)
    /// A day's English voice-over: scripted, recorded and mixed.
    case voice(day: Int)
    /// A day's narration in other languages, after its English was confirmed.
    case languages(day: Int, [Language])

    public var title: String {
        switch self {
        case .plan: "Plan"
        case .build(let days): days.count == 1 ? "Build" : "Build \(days.count) days"
        case .draft: "Sheet"
        case .render: "Render"
        case .beatmap: "Beatmap"
        case .voice: "Voice-over"
        case .languages(_, let languages): languages.count == 1 ? languages[0].title : "\(languages.count) languages"
        }
    }

    public var slug: String {
        switch self {
        case .plan: "plan"
        case .build: "build"
        case .draft: "draft"
        case .render: "render"
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

/// What a model read and wrote. `input` is the prompt it read, `cacheRead` the part of it already
/// in its cache from the call before (not read again), `output` what it wrote, thinking included.
public struct TokenUsage: Codable, Sendable, Equatable, Hashable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    /// Unused on this Mac; kept so older logs read.
    public var cacheWrite: Int
    /// Seconds spent reading the prompt and writing the answer.
    public var seconds: Double

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, seconds: Double = 0) {
        self.input = input; self.output = output; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite; self.seconds = seconds
    }

    enum CodingKeys: String, CodingKey { case input, output, cacheRead, cacheWrite, seconds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = (try? c.decode(Int.self, forKey: .input)) ?? 0
        output = (try? c.decode(Int.self, forKey: .output)) ?? 0
        cacheRead = (try? c.decode(Int.self, forKey: .cacheRead)) ?? 0
        cacheWrite = (try? c.decode(Int.self, forKey: .cacheWrite)) ?? 0
        seconds = (try? c.decode(Double.self, forKey: .seconds)) ?? 0
    }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, output: a.output + b.output, cacheRead: a.cacheRead + b.cacheRead,
                   cacheWrite: a.cacheWrite + b.cacheWrite, seconds: a.seconds + b.seconds)
    }

    public var isEmpty: Bool { input + output + cacheRead + cacheWrite == 0 }

    /// Share of the prompt that came from the cache.
    public var cacheHitRate: Double {
        let prompt = input + cacheRead
        return prompt == 0 ? 0 : Double(cacheRead) / Double(prompt)
    }

    /// Tokens written per second, over the whole call.
    public var tokensPerSecond: Double { seconds > 0 ? Double(output) / seconds : 0 }

    /// "24,812 read (20,104 from cache), 6,210 written in 4 min 12 s".
    public var line: String {
        var parts = ["\((input + cacheRead).formatted()) read"]
        if cacheRead > 0 { parts[0] += " (\(cacheRead.formatted()) from cache)" }
        parts.append("\(output.formatted()) written")
        return parts.joined(separator: ", ") + (seconds > 0 ? " in \(Self.duration(seconds))" : "")
    }

    /// "48 s", "4 min 12 s", "1 h 3 min".
    public static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min \(s % 60) s" }
        return "\(s / 3600) h \((s % 3600) / 60) min"
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
    /// What the run spoke, when it did.
    public var voice: VoiceUsage?
    /// Relative to the campaign folder.
    public var logPath: String

    public init(id: UUID = UUID(), campaignID: UUID, kind: RunKind, model: String, startedAt: Date = Date(), logPath: String) {
        self.id = id; self.campaignID = campaignID; self.kind = kind; self.model = model; self.startedAt = startedAt
        self.finishedAt = nil; self.outcome = .running; self.steps = []; self.usage = TokenUsage(); self.logPath = logPath
    }
}
