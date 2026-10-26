//
//  RunLog.swift
//  AdverbCore
//
//  WHAT: A generation run's log: lines with times in logs/<started>-<kind>.log as it goes, and
//        the run's record (steps, usage, outcome) in the .json beside it when it ends.
//

import Foundation

public final class RunLog: @unchecked Sendable {
    public let url: URL
    public let jsonURL: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    private var run: GenerationRun
    private let clock: DateFormatter

    public init(paths: CampaignPaths, campaignID: UUID, kind: RunKind, model: String) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let suffix: String
        switch kind {
        case .build(let days) where days.count == 1: suffix = "-day\(days[0])"
        case .beatmap(let day): suffix = "-day\(day)"
        default: suffix = ""
        }
        url = paths.logs.appendingPathComponent("\(stamp)-\(kind.slug)\(suffix).log")
        jsonURL = url.deletingPathExtension().appendingPathExtension("json")
        run = GenerationRun(campaignID: campaignID, kind: kind, model: model, logPath: paths.relative(url))
        clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX"); clock.dateFormat = "HH:mm:ss"
        try? FileManager.default.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    public var id: UUID { run.id }

    public func line(_ text: String) {
        let row = "\(clock.string(from: Date()))  \(text)\n"
        lock.withLock { try? handle?.write(contentsOf: Data(row.utf8)) }
    }

    public func step(_ name: String, day: Int? = nil) {
        lock.withLock {
            if let last = run.steps.indices.last, run.steps[last].finishedAt == nil { run.steps[last].finishedAt = Date() }
            run.steps.append(StepRecord(name: name, dayIndex: day))
        }
        line("▸ \(name)")
    }

    public func add(_ usage: TokenUsage) { lock.withLock { run.usage = run.usage + usage } }

    public var usage: TokenUsage { lock.withLock { run.usage } }

    public func finish(_ outcome: RunOutcome) {
        let record: GenerationRun = lock.withLock {
            if let last = run.steps.indices.last, run.steps[last].finishedAt == nil { run.steps[last].finishedAt = Date() }
            run.outcome = outcome
            run.finishedAt = Date()
            return run
        }
        switch outcome {
        case .failed(let message): line("✗ \(message)")
        case .cancelled: line("■ cancelled")
        default: line("✓ done")
        }
        let u = record.usage
        line("tokens: \(u.input) in, \(u.output) out, \(u.cacheRead) from cache, \(u.cacheWrite) cached · ≈ $\(String(format: "%.2f", u.estimatedUSD(model: record.model)))")
        try? JSONCoding.write(record, to: jsonURL)
        lock.withLock { try? handle?.close(); handle = nil }
    }
}
