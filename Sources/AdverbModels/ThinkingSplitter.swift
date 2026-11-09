//
//  ThinkingSplitter.swift
//  AdverbModels
//
//  WHAT: A model's stream split into its thinking and its answer, as it arrives: everything inside a
//        thinking block (or from the start, when the prompt opened one) is thinking. The block is
//        Qwen's and Nemotron's `<think>…</think>` or Gemma 4's `<|channel>thought…<channel|>`.
//  PIN:  A tag can arrive split across pieces ("</th" + "ink>"): the tail that could still become a
//        tag is held back until the next piece says what it is.
//

import Foundation

struct ThinkingSplitter {
    enum Piece: Equatable { case thinking(String), text(String) }

    struct Tags: Equatable, Sendable {
        let open: String
        let close: String
    }

    static let qwen = Tags(open: "<think>", close: "</think>")
    static let gemma = Tags(open: "<|channel>thought", close: "<channel|>")
    static let known = [qwen, gemma]

    /// Kept for the budget's close on a model whose tags were never seen (Qwen's are the default).
    static let open = qwen.open
    static let close = qwen.close

    private(set) var isThinking: Bool
    /// The pair in use: the one the prompt opened, or the first one the model wrote.
    private(set) var tags: Tags
    private var pending = ""
    /// Nothing but whitespace has been answered yet: an opening tag here opens thinking.
    private var atStart = true

    init(startsThinking: Bool, tags: Tags = ThinkingSplitter.qwen) {
        isThinking = startsThinking
        self.tags = tags
    }

    mutating func feed(_ text: String) -> [Piece] {
        pending += text
        var out: [Piece] = []
        while !pending.isEmpty {
            if isThinking {
                if let r = pending.range(of: tags.close) {
                    let before = String(pending[..<r.lowerBound])
                    if !before.isEmpty { out.append(.thinking(before)) }
                    pending = String(pending[r.upperBound...])
                    isThinking = false
                    atStart = true
                    continue
                }
                let keep = Self.partialSuffix(pending, of: [tags.close])
                let emit = String(pending.dropLast(keep))
                if !emit.isEmpty { out.append(.thinking(emit)) }
                pending = String(pending.suffix(keep))
                break
            } else {
                if atStart {
                    let trimmed = pending.drop { $0.isWhitespace }
                    if trimmed.isEmpty { break }
                    if let pair = Self.known.first(where: { trimmed.hasPrefix($0.open) }) {
                        pending = String(trimmed.dropFirst(pair.open.count))
                        tags = pair
                        isThinking = true
                        continue
                    }
                    if Self.known.contains(where: { $0.open.hasPrefix(String(trimmed)) }) { break }
                    atStart = false
                    pending = String(trimmed)
                }
                // A stray close tag (a template that thinks without saying so) ends nothing here.
                for pair in Self.known { pending = pending.replacingOccurrences(of: pair.close, with: "") }
                let keep = Self.partialSuffix(pending, of: Self.known.map(\.close))
                let emit = String(pending.dropLast(keep))
                if !emit.isEmpty { out.append(.text(emit)) }
                pending = String(pending.suffix(keep))
                break
            }
        }
        return out
    }

    mutating func finish() -> [Piece] {
        defer { pending = "" }
        guard !pending.isEmpty else { return [] }
        return [isThinking ? .thinking(pending) : .text(pending)]
    }

    /// How many characters at the end of `text` could begin one of `tags`.
    static func partialSuffix(_ text: String, of tags: [String]) -> Int {
        tags.map { partialSuffix(text, of: $0) }.max() ?? 0
    }

    static func partialSuffix(_ text: String, of tag: String) -> Int {
        var n = min(text.count, tag.count - 1)
        while n > 0 {
            if tag.hasPrefix(String(text.suffix(n))) { return n }
            n -= 1
        }
        return 0
    }

    /// The pair a prompt's tail leaves open (the template began the thinking), if any.
    static func openAtEnd(of tail: String) -> Tags? {
        for pair in known {
            guard let open = tail.range(of: pair.open, options: .backwards) else { continue }
            if !tail[open.upperBound...].contains(pair.close) { return pair }
        }
        return nil
    }
}
