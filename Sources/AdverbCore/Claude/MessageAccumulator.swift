//
//  MessageAccumulator.swift
//  AdverbCore
//
//  WHAT: Reads a Messages API stream, one SSE line at a time, into the message it describes:
//        content blocks by index (text, thinking with its signature, server tool calls with their
//        JSON input, server tool results, fallback markers), the stop reason and its details, and
//        token usage including the cache. Pure and free of I/O, so it is tested on captured frames.
//

import Foundation

public struct MessageAccumulator: Sendable {
    public private(set) var message = ClaudeMessage()
    public private(set) var finished = false
    private var blocks: [Int: [String: JSONValue]] = [:]
    private var partialJSON: [Int: String] = [:]

    public init() {}

    /// The payload of an SSE `data:` line, or nil for anything else (`event:` lines, `:` keepalive
    /// comments, blank separators). The space after the colon is optional in the SSE spec.
    public static func payload(of line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    }

    /// Folds one line in, returning what is worth showing now.
    public mutating func consume(_ line: String) throws -> [ClaudeEvent] {
        guard let payload = Self.payload(of: line), !payload.isEmpty,
              let event = try? JSONValue.parse(payload), let type = event["type"]?.stringValue else { return [] }
        switch type {
        case "message_start":
            let m = event["message"] ?? .null
            message.id = m["id"]?.stringValue ?? ""
            message.model = m["model"]?.stringValue ?? ""
            message.usage = Self.usage(m["usage"]) 
            return [.usage(message.usage)]
        case "content_block_start":
            guard let index = event["index"]?.intValue, case .object(var block)? = event["content_block"] else { return [] }
            if block["type"]?.stringValue == "text" { block["text"] = .string(block["text"]?.stringValue ?? "") }
            if block["type"]?.stringValue == "thinking" { block["thinking"] = .string(block["thinking"]?.stringValue ?? "") }
            blocks[index] = block
            switch block["type"]?.stringValue {
            case "server_tool_use":
                return [.activity(Self.toolActivity(block))]
            case "fallback":
                let to = block["to"]?["model"]?.stringValue ?? "a fallback model"
                return [.activity("Continuing on \(to)")]
            default:
                return []
            }
        case "content_block_delta":
            guard let index = event["index"]?.intValue, let delta = event["delta"], var block = blocks[index] else { return [] }
            switch delta["type"]?.stringValue {
            case "text_delta":
                let piece = delta["text"]?.stringValue ?? ""
                block["text"] = .string((block["text"]?.stringValue ?? "") + piece)
                blocks[index] = block
                return piece.isEmpty ? [] : [.text(piece)]
            case "thinking_delta":
                let piece = delta["thinking"]?.stringValue ?? ""
                block["thinking"] = .string((block["thinking"]?.stringValue ?? "") + piece)
                blocks[index] = block
                return piece.isEmpty ? [] : [.activity(piece)]
            case "signature_delta":
                block["signature"] = .string((block["signature"]?.stringValue ?? "") + (delta["signature"]?.stringValue ?? ""))
                blocks[index] = block
            case "input_json_delta":
                partialJSON[index, default: ""] += delta["partial_json"]?.stringValue ?? ""
            default:
                break
            }
            return []
        case "content_block_stop":
            guard let index = event["index"]?.intValue, var block = blocks[index] else { return [] }
            if let json = partialJSON.removeValue(forKey: index), !json.isEmpty, let input = try? JSONValue.parse(json) {
                block["input"] = input
                blocks[index] = block
                if block["type"]?.stringValue == "server_tool_use" { return [.activity(Self.toolActivity(block))] }
            }
            return []
        case "message_delta":
            if let reason = event["delta"]?["stop_reason"]?.stringValue { message.stopReason = reason }
            if let details = event["delta"]?["stop_details"], !details.isNull { message.stopDetails = details }
            if let usage = event["usage"] {
                if let out = usage["output_tokens"]?.intValue { message.usage.output = out }
                if let read = usage["cache_read_input_tokens"]?.intValue { message.usage.cacheRead = read }
                if let write = usage["cache_creation_input_tokens"]?.intValue { message.usage.cacheWrite = write }
                if let input = usage["input_tokens"]?.intValue, input > 0 { message.usage.input = input }
            }
            return [.usage(message.usage)]
        case "message_stop":
            finished = true
            message.content = blocks.keys.sorted().compactMap { blocks[$0].map(JSONValue.object) }
            return [.final(message)]
        case "error":
            throw ClaudeError.stream(event["error"]?["message"]?.stringValue ?? "The API returned an error mid-stream.")
        default:
            return []
        }
    }

    /// The message so far, for a stream that ended without `message_stop`.
    public var partial: ClaudeMessage {
        var m = message
        m.content = blocks.keys.sorted().compactMap { blocks[$0].map(JSONValue.object) }
        return m
    }

    static func usage(_ json: JSONValue?) -> TokenUsage {
        TokenUsage(input: json?["input_tokens"]?.intValue ?? 0, output: json?["output_tokens"]?.intValue ?? 0,
                   cacheRead: json?["cache_read_input_tokens"]?.intValue ?? 0,
                   cacheWrite: json?["cache_creation_input_tokens"]?.intValue ?? 0)
    }

    static func toolActivity(_ block: [String: JSONValue]) -> String {
        if let url = block["input"]?["url"]?.stringValue {
            return "Reading \(URL(string: url)?.host ?? url)"
        }
        return block["name"]?.stringValue == "web_fetch" ? "Fetching a page" : "Using \(block["name"]?.stringValue ?? "a tool")"
    }
}
