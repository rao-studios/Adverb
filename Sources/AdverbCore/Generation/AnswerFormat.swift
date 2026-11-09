//
//  AnswerFormat.swift
//  AdverbCore
//
//  WHAT: The shape an answer must take, said to the model at the end of the request: free text,
//        one JSON object, or a document — a whole HTML page first, then a line, then a small JSON
//        object about it. And the shape itself, written as a skeleton a model can follow.
//  PIN:  A page is never a JSON string. Ten thousand tokens of HTML, CSS and script escaped inside
//        quotes is where a small model breaks; written as itself, then a sentinel, it is the same
//        page the kit's template shows, and the JSON after it stays small.
//  PIN:  The skeleton keeps the schema's key order (Schemas builds objects in order): a model
//        writes the keys as shown, so the plan's summary comes before its thirty days.
//

import Foundation

public enum AnswerFormat: Sendable, Equatable {
    case text
    /// One JSON object of this schema.
    case json(JSONValue)
    /// An HTML page, then `AnswerParser.sentinel`, then a JSON object of `trailer`. With
    /// `optionalPage` the page may be left out (a review that finds nothing to change).
    case document(trailer: JSONValue, optionalPage: Bool)

    /// What the model is told about the format, after the request.
    public var instructions: String? {
        switch self {
        case .text:
            return nil
        case .json(let schema):
            return """
            Answer with one JSON object and nothing else: no words before or after it, no code fence. \
            Every key is required, in this order; an array may hold any number of items:
            \(Self.skeleton(schema))
            """
        case .document(let trailer, let optionalPage):
            let page = optionalPage
                ? "1. If the page needs changes, the whole corrected page: plain HTML from `<!doctype html>` to `</html>`, not in a code fence. If it needs none, write no page at all."
                : "1. The whole page: plain HTML from `<!doctype html>` to `</html>`, not in a code fence and not escaped."
            return """
            Answer in two parts and nothing else:
            \(page)
            2. Then a line that says exactly `\(AnswerParser.sentinel)`, and after it one JSON object, every key required, in this order:
            \(Self.skeleton(trailer))
            """
        }
    }

    /// How an answer in this format begins, for a model that does not think first: it is started
    /// there and cannot open with a plan, a preamble or a fence.
    public var opening: String? {
        switch self {
        case .text: nil
        case .json: "{"
        case .document(_, let optionalPage): optionalPage ? nil : "<!doctype html>"
        }
    }

    /// The schema as an instance-shaped template: `"…"` for text, `0` for numbers, the choices of
    /// an enum, one item in each array.
    public static func skeleton(_ schema: JSONValue, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)
        if let options = schema["enum"]?.arrayValue {
            let list = options.compactMap(\.scalarDescription)
            return schema["type"]?.stringValue == "string" ? "\"\(list.joined(separator: " | "))\"" : list.joined(separator: " | ")
        }
        switch schema["type"]?.stringValue {
        case "object":
            let properties = schema["properties"]?.objectValue ?? [:]
            let keys = schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? properties.keys.sorted()
            guard !keys.isEmpty else { return "{}" }
            let rows = keys.map { key in "\(inner)\"\(key)\": \(skeleton(properties[key] ?? [:], indent: indent + 1))" }
            return "{\n" + rows.joined(separator: ",\n") + "\n\(pad)}"
        case "array":
            return "[" + skeleton(schema["items"] ?? [:], indent: indent) + ", …]"
        case "string":
            return schema["format"]?.stringValue == "date" ? "\"YYYY-MM-DD\"" : "\"…\""
        case "integer": return "0"
        case "number": return "0.0"
        case "boolean": return "true"
        default: return "null"
        }
    }
}
