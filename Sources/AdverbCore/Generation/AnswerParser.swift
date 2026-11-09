//
//  AnswerParser.swift
//  AdverbCore
//
//  WHAT: A model's answer read in the format it was asked for: the JSON object in it (a code fence,
//        prose around it, a trailing comma, a raw newline in a string, a backslash that escapes
//        nothing, an answer cut off mid-object — all forgiven), or a page and the JSON after it.
//  IN:   The answer's text, its thinking already taken out (AdverbModels).
//  OUT:  A JSONValue, or the response type decoded from it; ModelError.unreadable says what was wrong
//        in words the fix round can send back.
//  PIN:  Craft's model-text salvage (CraftCore JSONValue.object(inModelText:), salvagingTruncation and
//        LenientMistralCalls.repairJSON), lifted. What the validators check after decoding is the
//        contract; this only gets the answer into a shape they can read.
//

import Foundation

public enum AnswerParser {
    public static let sentinel = "=== ADVERB JSON ==="

    // MARK: - Decoding

    public static func value(_ text: String, format: AnswerFormat) throws -> JSONValue {
        switch format {
        case .text:
            return .string(text)
        case .json:
            guard let object = object(in: text) else {
                throw ModelError.unreadable(text.contains("{") ? "the JSON object did not parse." : "there was no JSON object in it.")
            }
            return object
        case .document(_, let optionalPage):
            let parts = document(in: text)
            if parts.html == nil, !optionalPage {
                throw ModelError.unreadable(parts.cut
                    ? "the page stops before </html>: it ran out of room. Write it shorter."
                    : "there was no page in it (from <!doctype html> to </html>).")
            }
            guard case .object(var fields)? = parts.trailer else {
                throw ModelError.unreadable("there was no JSON object after the line \(sentinel).")
            }
            fields["html"] = .string(parts.html ?? "")
            return .object(fields)
        }
    }

    public static func decode<T: Decodable>(_ type: T.Type, from text: String, format: AnswerFormat) throws -> T {
        let value = try value(text, format: format)
        do {
            return try JSONDecoder().decode(T.self, from: value.data())
        } catch let error as DecodingError {
            throw ModelError.unreadable(describe(error))
        }
    }

    static func describe(_ error: DecodingError) -> String {
        func path(_ keys: [CodingKey]) -> String {
            keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        switch error {
        case .keyNotFound(let key, let context): return "\(path(context.codingPath + [key])) is missing."
        case .typeMismatch(let type, let context): return "\(path(context.codingPath)) is not a \(type)."
        case .valueNotFound(let type, let context): return "\(path(context.codingPath)) has no \(type)."
        case .dataCorrupted(let context): return context.debugDescription
        @unknown default: return "\(error)"
        }
    }

    // MARK: - A page and its trailer

    /// The page (first `<!doctype` or `<html` to the last `</html>`) and the JSON object after the
    /// sentinel, else after the page, else the whole answer's. `cut` is a page that began and
    /// never ended.
    public static func document(in text: String) -> (html: String?, trailer: JSONValue?, cut: Bool) {
        let lower = text.lowercased()
        let start = lower.range(of: "<!doctype").map(\.lowerBound) ?? lower.range(of: "<html").map(\.lowerBound)
        var html: String?
        var afterPage = text.startIndex
        var cut = false
        if let start, let end = lower.range(of: "</html>", options: .backwards), end.lowerBound > start {
            let s = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: start))
            let e = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: end.upperBound))
            html = String(text[s..<e])
            afterPage = e
        } else if start != nil {
            cut = true
        }
        var trailer: JSONValue?
        if let mark = text.range(of: sentinel, options: .backwards) {
            trailer = object(in: String(text[mark.upperBound...]))
        }
        if trailer == nil, html != nil { trailer = object(in: String(text[afterPage...])) }
        if trailer == nil, html == nil, !cut { trailer = object(in: text) }
        return (html, trailer, cut)
    }

    // MARK: - A JSON object in model text

    /// The JSON object in `text`: the first fenced block if there is one, from its first `{` to its
    /// last `}`, made strict, else salvaged from where it was cut off.
    public static func object(in text: String) -> JSONValue? {
        var body = text
        if let fence = body.range(of: "```") {
            let afterOpen = body[fence.upperBound...]
            let start = afterOpen.firstIndex(where: \.isNewline).map { afterOpen.index(after: $0) } ?? afterOpen.startIndex
            let rest = afterOpen[start...]
            let fenced = String(rest.range(of: "```").map { rest[..<$0.lowerBound] } ?? rest)
            if fenced.contains("{") { body = fenced }
        }
        guard let open = body.firstIndex(of: "{") else { return nil }
        if let close = body.lastIndex(of: "}"), open < close, let value = parseObject(String(body[open...close])) {
            return value
        }
        return salvagingTruncation(String(body[open...]))
    }

    static func parseObject(_ json: String) -> JSONValue? {
        for candidate in [json, repairJSON(json), withoutTrailingCommas(repairJSON(json))] {
            if let value = try? JSONValue.parse(Data(candidate.utf8)), case .object = value { return value }
        }
        return nil
    }

    /// An object cut off mid-answer, closed: back to the last object that was finished (a half-written
    /// day or line is dropped, not kept with empty fields), else to the last complete element.
    static func salvagingTruncation(_ text: String) -> JSONValue? {
        let midValue = endsInsideAString(text)
        let lastClosed = text.lastIndex(of: "}").map { String(text[...$0]) }
        let candidates = midValue
            ? [lastClosed, trimmedToLast(",", in: text), text, trimmedToLast("[", in: text)]
            : [lastClosed, text, trimmedToLast(",", in: text), trimmedToLast("[", in: text)]
        for candidate in candidates {
            guard let candidate, let closed = closingOpenContainers(candidate) else { continue }
            if let value = parseObject(closed) { return value }
        }
        return nil
    }

    static func endsInsideAString(_ text: String) -> Bool {
        var inString = false, escaped = false
        for c in text {
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true }
        }
        return inString
    }

    static func closingOpenContainers(_ text: String) -> String? {
        var stack: [Character] = []
        var inString = false, escaped = false
        for c in text {
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"": inString = true
            case "{", "[": stack.append(c)
            case "}": if stack.last == "{" { stack.removeLast() }
            case "]": if stack.last == "[" { stack.removeLast() }
            default: break
            }
        }
        guard !stack.isEmpty else { return nil }
        var out = text
        if inString { out += "\"" }
        while let last = out.last, last.isWhitespace || last == "," || last == ":" { out.removeLast() }
        return out + String(stack.reversed().map { $0 == "{" ? "}" : "]" })
    }

    static func trimmedToLast(_ character: Character, in text: String) -> String? {
        text.lastIndex(of: character).map { String(text[..<$0]) }
    }

    /// Inside strings: a backslash that starts no escape is doubled, raw newlines and tabs escaped,
    /// a backslash before a backtick dropped.
    static func repairJSON(_ json: String) -> String {
        var out = ""
        out.reserveCapacity(json.count + 16)
        let cs = Array(json)
        var inString = false
        var i = 0
        while i < cs.count {
            let c = cs[i]
            if !inString {
                if c == "\"" { inString = true }
                out.append(c); i += 1; continue
            }
            switch c {
            case "\"": inString = false; out.append(c)
            case "\\":
                let next = i + 1 < cs.count ? cs[i + 1] : nil
                if let next, "\"\\/bfnrt".contains(next) {
                    out.append(c); out.append(next); i += 1
                } else if next == "u", i + 5 < cs.count, cs[(i + 2)...(i + 5)].allSatisfy(\.isHexDigit) {
                    out.append(c)
                } else if next == "`" {
                    out.append("`"); i += 1
                } else {
                    out += "\\\\"
                }
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default: out.append(c)
            }
            i += 1
        }
        return out
    }

    /// `[1, 2,]` and `{"a": 1,}` made strict (outside strings).
    static func withoutTrailingCommas(_ json: String) -> String {
        var out = ""
        var inString = false, escaped = false
        var pendingComma = false
        var whitespace = ""
        for c in json {
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            if pendingComma {
                if c.isWhitespace { whitespace.append(c); continue }
                if c != "}" && c != "]" { out.append(",") }
                out += whitespace
                pendingComma = false; whitespace = ""
            }
            if c == "," { pendingComma = true; continue }
            if c == "\"" { inString = true }
            out.append(c)
        }
        if pendingComma { out.append(",") }
        return out
    }
}
