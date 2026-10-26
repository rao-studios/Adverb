//
//  ClaudeClient.swift
//  AdverbCore
//
//  WHAT: The Claude Messages API over URLSession: one request, streamed, read into a message.
//        Structured outputs, adaptive thinking with readable summaries, server-side fallbacks on
//        a refusal, the web fetch server tool with `pause_turn` continuation, retries with
//        backoff, and a watchdog for a stream that goes quiet.
//  PIN:  anthropic-version 2026-10-21: no sampling parameters on this version. Thinking cannot
//        be turned off on Claude Opus 5.5 / Fable 5.1, and `budget_tokens` is a 400 there:
//        depth is `output_config.effort`, set explicitly because Opus 5.5 defaults to medium.
//        Check `stop_reason` before reading content: a refusal is an HTTP 200.
//  PIN:  The watchdog is Gita's (StreamTransport): the clock starts before the request does,
//        because `URLSession.bytes(for:)` itself can hang before a byte arrives. Long thinking
//        can be quiet for minutes, but `ping` frames count as life.
//

import Foundation

public struct ClaudeConfig: Sendable, Equatable {
    public var apiKey: Secret
    public var model: String
    public var effort: String
    public var maxTokens: Int
    public var fallbacks: Bool
    public var baseURL: URL
    public var firstFrameTimeout: TimeInterval
    public var idleTimeout: TimeInterval

    public init(apiKey: Secret, model: String = "claude-opus-5-5", effort: String = "high", maxTokens: Int = 64_000,
                fallbacks: Bool = true, baseURL: URL = URL(string: "https://api.anthropic.com")!,
                firstFrameTimeout: TimeInterval = 120, idleTimeout: TimeInterval = 240) {
        self.apiKey = apiKey; self.model = model; self.effort = effort; self.maxTokens = maxTokens
        self.fallbacks = fallbacks; self.baseURL = baseURL; self.firstFrameTimeout = firstFrameTimeout; self.idleTimeout = idleTimeout
    }

    /// Server-side fallback is offered for these models (`fallbacks: "default"`); Haiku has none.
    var supportsFallbacks: Bool { !model.hasPrefix("claude-haiku") }
}

public struct ClaudeClient: Sendable {
    public static let apiVersion = "2026-10-21"
    public static let fallbackBeta = "server-side-fallback-2026-07-01"

    public let config: ClaudeConfig
    let session: URLSession

    public init(config: ClaudeConfig, session: URLSession = .shared) {
        self.config = config; self.session = session
    }

    // MARK: - Request

    /// The JSON body for `request` (streaming). Public so its shape is tested.
    public func body(_ request: ClaudeRequest) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(config.model),
            "max_tokens": .number(Double(request.maxTokens ?? config.maxTokens)),
            "stream": true,
            "system": .array(request.system.map(\.json)),
            "messages": .array(request.messages.map(\.json)),
            "thinking": ["type": "adaptive", "display": "summarized"],
        ]
        var output: [String: JSONValue] = ["effort": .string(request.effort ?? config.effort)]
        if let schema = request.schema { output["format"] = ["type": "json_schema", "schema": schema] }
        body["output_config"] = .object(output)
        if !request.tools.isEmpty { body["tools"] = .array(request.tools) }
        if config.fallbacks, config.supportsFallbacks { body["fallbacks"] = "default" }
        return .object(body)
    }

    public func urlRequest(_ request: ClaudeRequest) throws -> URLRequest {
        var r = URLRequest(url: config.baseURL.appendingPathComponent("v1/messages"))
        r.httpMethod = "POST"
        r.timeoutInterval = 900
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(config.apiKey.value, forHTTPHeaderField: "x-api-key")
        r.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if config.fallbacks, config.supportsFallbacks { r.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta") }
        r.httpBody = try body(request).data()
        return r
    }

    // MARK: - Complete

    /// Sends `request` and returns the final message, handing every event to `onEvent` as it
    /// streams. Continues `pause_turn` (server tools) up to five times; retries what is worth
    /// retrying; throws on a refusal or a cut-off answer.
    public func complete(_ request: ClaudeRequest, onEvent: @escaping @Sendable (ClaudeEvent) -> Void = { _ in }) async throws -> ClaudeMessage {
        var request = request
        var usage = TokenUsage()
        var content: [JSONValue] = []
        for _ in 0..<6 {
            let attempt = request
            let message = try await withRetries { try await self.streamOnce(attempt, onEvent: onEvent) }
            usage = usage + message.usage
            content += message.content
            switch message.stopReason {
            case "pause_turn":
                // The server paused a long tool turn: send it back as it is, and it goes on.
                request.messages.append(.assistant(message.content))
                continue
            case "refusal":
                throw ClaudeError.refused(category: message.stopDetails?["category"]?.stringValue,
                                          explanation: message.stopDetails?["explanation"]?.stringValue)
            case "max_tokens":
                throw ClaudeError.truncated
            default:
                var final = message
                final.usage = usage
                final.content = content
                onEvent(.usage(usage))
                return final
            }
        }
        throw ClaudeError.stream("The model paused its turn too many times.")
    }

    /// The structured output, decoded.
    public static func decode<T: Decodable>(_ type: T.Type, from message: ClaudeMessage) throws -> T {
        let text = message.text
        guard let data = text.data(using: .utf8), !text.isEmpty else { throw ClaudeError.decoding("no text in the answer") }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ClaudeError.decoding("\(error)") }
    }

    /// A free check that the key works and the model exists: GET /v1/models/{model}.
    public func ping() async throws {
        var r = URLRequest(url: config.baseURL.appendingPathComponent("v1/models/\(config.model)"))
        r.setValue(config.apiKey.value, forHTTPHeaderField: "x-api-key")
        r.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        r.timeoutInterval = 30
        let (data, response) = try await session.data(for: r)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ClaudeError.http(code, String(decoding: data, as: UTF8.self)) }
    }

    // MARK: - One stream

    func streamOnce(_ request: ClaudeRequest, onEvent: @escaping @Sendable (ClaudeEvent) -> Void) async throws -> ClaudeMessage {
        let urlRequest = try self.urlRequest(request)
        let activity = ActivityClock()
        let first = config.firstFrameTimeout, idle = config.idleTimeout
        let session = self.session
        return try await withThrowingTaskGroup(of: ClaudeMessage?.self) { group in
            group.addTask {
                let (bytes, response) = try await session.bytes(for: urlRequest)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    var body = ""
                    for try await line in bytes.lines { activity.touch(); body += line }
                    throw ClaudeError.http(http.statusCode, body)
                }
                var accumulator = MessageAccumulator()
                for try await line in bytes.lines {
                    activity.touch()
                    try Task.checkCancellation()
                    for event in try accumulator.consume(line) {
                        if case .final = event { continue }
                        onEvent(event)
                    }
                    if accumulator.finished { return accumulator.message }
                }
                // The connection closed without message_stop.
                throw ClaudeError.stream("The stream ended early.")
            }
            group.addTask {
                while true {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    let (silent, sawFrame) = activity.elapsed()
                    if silent > (sawFrame ? idle : first) { throw ClaudeError.timedOut }
                }
            }
            defer { group.cancelAll() }
            while let result = try await group.next() {
                if let message = result { return message }
            }
            throw ClaudeError.stream("The stream ended early.")
        }
    }

    func withRetries(_ attempt: @Sendable () async throws -> ClaudeMessage) async throws -> ClaudeMessage {
        let delays: [UInt64] = [2, 8, 20]
        var last: Error = ClaudeError.stream("no attempt")
        for i in 0...delays.count {
            do { return try await attempt() } catch let error as ClaudeError where error.isRetryable && i < delays.count {
                last = error
                try await Task.sleep(nanoseconds: delays[i] * 1_000_000_000)
            } catch let error as URLError where i < delays.count && error.code != .cancelled {
                last = ClaudeError.stream(error.localizedDescription)
                try await Task.sleep(nanoseconds: delays[i] * 1_000_000_000)
            }
        }
        throw last
    }
}

/// Last-frame clock shared between a stream and its watchdog.
final class ActivityClock: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date()
    private var sawFrame = false

    func touch() { lock.withLock { last = Date(); sawFrame = true } }
    func elapsed() -> (TimeInterval, Bool) { lock.withLock { (Date().timeIntervalSince(last), sawFrame) } }
}
