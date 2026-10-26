//
//  AgentStream.swift
//  AdverbAgents
//
//  WHAT: The body every Adverb agent's `run` shares: a task that does the job and yields its
//        events, cancelled when the run is.
//

import Foundation

enum AgentStream {
    static func run(_ job: @escaping @Sendable (_ emit: @escaping @Sendable (GenerationEvent) -> Void) async throws -> Void)
        -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await job { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Thinking summaries and text arrive a few characters at a time: fold them so main commits
    /// once per drain.
    static func coalesce(_ a: GenerationEvent, _ b: GenerationEvent) -> GenerationEvent? {
        switch (a, b) {
        case (.activity(let x), .activity(let y)): .activity(x + y)
        case (.progress, .progress(let y)): .progress(y)
        case (.usage, .usage(let y)): .usage(y)
        default: nil
        }
    }
}
