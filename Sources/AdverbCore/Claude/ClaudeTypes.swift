//
//  ClaudeTypes.swift
//  AdverbCore
//
//  WHAT: The shapes Adverb speaks to the Claude Messages API in: a request (system blocks with
//        cache breakpoints, messages, a structured-output schema, server tools), the message that
//        comes back, the events a stream yields, and the errors it can end in.
//  PIN:  Swift has no Anthropic SDK, so this is raw HTTP (POST /v1/messages). Content blocks are
//        JSONValue so an assistant turn, server-tool blocks and thinking signatures included,
//        goes back unchanged on `pause_turn`.
//

import Foundation

public struct SystemBlock: Sendable, Equatable {
    public var text: String
    /// A cache breakpoint after this block (1 hour: thirty builds outlast the 5-minute default).
    public var cache: Bool

    public init(_ text: String, cache: Bool = false) { self.text = text; self.cache = cache }

    var json: JSONValue {
        var block: [String: JSONValue] = ["type": "text", "text": .string(text)]
        if cache { block["cache_control"] = ["type": "ephemeral", "ttl": "1h"] }
        return .object(block)
    }
}

public struct ClaudeMessageParam: Sendable, Equatable {
    public var role: String
    public var content: [JSONValue]

    public init(role: String, content: [JSONValue]) { self.role = role; self.content = content }

    public static func user(_ blocks: [JSONValue]) -> ClaudeMessageParam { .init(role: "user", content: blocks) }
    public static func user(_ text: String) -> ClaudeMessageParam { .init(role: "user", content: [.text(text)]) }
    public static func assistant(_ blocks: [JSONValue]) -> ClaudeMessageParam { .init(role: "assistant", content: blocks) }

    var json: JSONValue { ["role": .string(role), "content": .array(content)] }
}

extension JSONValue {
    /// A text content block, with an optional cache breakpoint.
    public static func text(_ text: String, cache: Bool = false) -> JSONValue {
        var block: [String: JSONValue] = ["type": "text", "text": .string(text)]
        if cache { block["cache_control"] = ["type": "ephemeral", "ttl": "1h"] }
        return .object(block)
    }

    /// A base64 JPEG image content block.
    public static func jpeg(_ data: Data) -> JSONValue {
        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": .string(data.base64EncodedString())]]
    }
}

public struct ClaudeRequest: Sendable, Equatable {
    public var system: [SystemBlock]
    public var messages: [ClaudeMessageParam]
    /// A JSON schema the final text must match (structured outputs).
    public var schema: JSONValue?
    public var tools: [JSONValue]
    public var maxTokens: Int?
    public var effort: String?

    public init(system: [SystemBlock], messages: [ClaudeMessageParam], schema: JSONValue? = nil, tools: [JSONValue] = [],
                maxTokens: Int? = nil, effort: String? = nil) {
        self.system = system; self.messages = messages; self.schema = schema; self.tools = tools
        self.maxTokens = maxTokens; self.effort = effort
    }

    /// The web fetch server tool, limited to `domains`.
    public static func webFetch(domains: [String], maxUses: Int = 8) -> JSONValue {
        var tool: [String: JSONValue] = ["type": "web_fetch_20260209", "name": "web_fetch", "max_uses": .number(Double(maxUses))]
        if !domains.isEmpty { tool["allowed_domains"] = .array(domains.map { .string($0) }) }
        return .object(tool)
    }
}

public struct ClaudeMessage: Sendable, Equatable {
    public var id: String
    public var model: String
    public var content: [JSONValue]
    public var stopReason: String?
    public var stopDetails: JSONValue?
    public var usage: TokenUsage

    public init(id: String = "", model: String = "", content: [JSONValue] = [], stopReason: String? = nil,
                stopDetails: JSONValue? = nil, usage: TokenUsage = TokenUsage()) {
        self.id = id; self.model = model; self.content = content; self.stopReason = stopReason
        self.stopDetails = stopDetails; self.usage = usage
    }

    /// Every text block, joined: for structured outputs, the JSON.
    public var text: String {
        content.compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }.joined()
    }

    /// Whether a fallback model served this turn (a `fallback` block marks the switch).
    public var fellBack: Bool { content.contains { $0["type"]?.stringValue == "fallback" } }
}

public enum ClaudeEvent: Sendable, Equatable {
    /// Something to show while it works: a thinking summary, "Reading ambient.rao.nyc".
    case activity(String)
    case text(String)
    case usage(TokenUsage)
    case final(ClaudeMessage)
}

public enum ClaudeError: Error, Equatable, CustomStringConvertible {
    case noKey
    case http(Int, String)
    case refused(category: String?, explanation: String?)
    case truncated
    case stream(String)
    case timedOut
    case decoding(String)
    case invalid(String)

    public var description: String {
        switch self {
        case .noKey: "No Claude API key. Add one in Settings."
        case .http(401, _): "The API key was refused (401). Check it in Settings."
        case .http(403, let body): "Not allowed (403): \(Self.message(body))"
        case .http(429, _): "Rate limited (429). Adverb retried and gave up; try again in a minute."
        case .http(let code, let body): "HTTP \(code): \(Self.message(body))"
        case .refused(let category, let explanation):
            "Claude declined this request" + (category.map { " (\($0))" } ?? "") + (explanation.map { ": \($0)" } ?? ".")
        case .truncated: "The answer ran past its length limit."
        case .stream(let message): message
        case .timedOut: "The connection went quiet and was closed."
        case .decoding(let message): "The answer was not in the expected shape: \(message)"
        case .invalid(let message): message
        }
    }

    /// The API's own message from an error body, else the body clipped.
    static func message(_ body: String) -> String {
        if let json = try? JSONValue.parse(body), let message = json.value(at: "error.message")?.stringValue { return message }
        return String(body.prefix(300))
    }

    var isRetryable: Bool {
        switch self {
        case .http(let code, _): code == 408 || code == 409 || code == 429 || code >= 500
        case .timedOut, .stream: true
        default: false
        }
    }
}
