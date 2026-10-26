//
//  ClaudeCall.swift
//  AdverbAgents
//
//  WHAT: One structured Claude call as a run makes it: thinking streamed as activity, tool use
//        noted in the log, usage added to the run, the answer decoded against its schema.
//  PIN:  If the API refuses the web fetch tool beside a structured output (a 400 naming tools),
//        the call is made once more without it, and the log says so: the planner still has the
//        project's own files.
//

import AdverbCore
import Foundation

enum ClaudeCall {
    static func structured<T: Decodable & Sendable>(_ type: T.Type, client: ClaudeClient, request: ClaudeRequest, log: RunLog,
                                                    emit: @escaping @Sendable (GenerationEvent) -> Void) async throws -> (T, ClaudeMessage) {
        let thinking = ThinkingBuffer()
        let onEvent: @Sendable (ClaudeEvent) -> Void = { event in
            switch event {
            case .activity(let text):
                emit(.activity(text))
                if text.hasPrefix("Reading ") || text.hasPrefix("Continuing on") || text.hasPrefix("Fetching") { log.line(text) }
                else { thinking.add(text) }
            case .usage, .text, .final: break
            }
        }
        var message: ClaudeMessage
        do {
            message = try await client.complete(request, onEvent: onEvent)
        } catch ClaudeError.http(400, let body) where !request.tools.isEmpty && body.localizedCaseInsensitiveContains("tool") {
            log.line("The API refused web fetch with a structured answer; asking again without it.")
            var plain = request
            plain.tools = []
            message = try await client.complete(plain, onEvent: onEvent)
        }
        if let summary = thinking.text, !summary.isEmpty { log.line("thinking: \(summary.prefix(800))") }
        log.add(message.usage)
        emit(.usage(log.usage))
        if message.fellBack { log.line("A fallback model (\(message.model)) answered.") }
        let value = try ClaudeClient.decode(T.self, from: message)
        return (value, message)
    }
}

final class ThinkingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    func add(_ s: String) { lock.withLock { if buffer.count < 4000 { buffer += s } } }
    var text: String? { lock.withLock { buffer.isEmpty ? nil : buffer } }
}
