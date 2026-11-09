//
//  ModelCall.swift
//  AdverbAgents
//
//  WHAT: One call to the model on this Mac as a run makes it: the answer's format said after the
//        request, the thinking streamed as activity, the answer streamed as it is written (what the
//        run strip shows), the tokens and time added to the run, the answer read in its format.
//  PIN:  An answer that cannot be read is sent back once, with what was wrong and the format again,
//        before the call fails: a local model's slip (a missing brace, a fence, a page cut short) is
//        far more often a one-off than a misunderstanding. What the validators find after that is
//        the job's own fix round.
//

import AdverbCore
import Foundation

enum ModelCall {
    static func structured<T: Decodable & Sendable>(_ type: T.Type, model: any LanguageModel, request: ModelRequest, log: RunLog,
                                                    repairs: Int = 1,
                                                    emit: @escaping @Sendable (GenerationEvent) -> Void) async throws -> (T, ModelAnswer) {
        var request = withInstructions(request)
        var attempt = 0
        while true {
            let answer = try await complete(model: model, request: request, log: log, emit: emit)
            do {
                let value = try AnswerParser.decode(T.self, from: answer.text, format: request.format)
                return (value, answer)
            } catch ModelError.unreadable(let why) {
                let kept = log.attach("\(request.label.replacingOccurrences(of: " ", with: "-"))-\(attempt + 1).txt", answer.text)
                guard attempt < repairs else {
                    log.line("\(request.label): the answer could not be read (\(why)); kept in \(kept.lastPathComponent)")
                    throw ModelError.unreadable(why)
                }
                attempt += 1
                log.line("\(request.label): the answer could not be read (\(why)); kept in \(kept.lastPathComponent); asking again")
                emit(.step("Asking again"))
                request.turns += [.assistant(answer.text),
                                  .user("Your answer could not be read: \(why) Answer again, complete, in the format asked."
                                        + (request.format.instructions.map { "\n\n" + $0 } ?? ""))]
            }
        }
    }

    /// The call itself: events to the run, usage to the log.
    static func complete(model: any LanguageModel, request: ModelRequest, log: RunLog,
                         emit: @escaping @Sendable (GenerationEvent) -> Void) async throws -> ModelAnswer {
        let before = log.usage
        let onEvent: @Sendable (ModelEvent) -> Void = { event in
            switch event {
            case .thinking(let text): emit(.activity(text))
            case .text(let text): emit(.writing(text))
            case .status(let text): emit(.log(text)); log.line(text)
            case .usage(let u): emit(.usage(before + u))
            }
        }
        let answer = try await model.complete(request, onEvent: onEvent)
        log.add(answer.usage)
        emit(.usage(log.usage))
        log.line("\(request.label.isEmpty ? "call" : request.label): \(answer.usage.line)"
                 + (answer.usage.tokensPerSecond > 0 ? String(format: " · %.1f tok/s", answer.usage.tokensPerSecond) : "")
                 + (answer.truncated ? " · stopped at its limit" : ""))
        if !answer.thinking.isEmpty { log.line("thinking: \(answer.thinking.prefix(800))") }
        return answer
    }

    /// The request with its format's instructions after the last user turn's text, and, when the
    /// model answers without thinking, its answer started in the format.
    static func withInstructions(_ request: ModelRequest) -> ModelRequest {
        var out = request
        if out.answerPrefix == nil, out.thinking == .off, !out.hasImages { out.answerPrefix = out.format.opening }
        guard let instructions = request.format.instructions, let last = request.turns.lastIndex(where: { $0.role == .user }) else { return out }
        out.turns[last].parts.append(.text("\n" + instructions))
        return out
    }
}
