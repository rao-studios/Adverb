//
//  KokoroLexer.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: Normalized text → words and the punctuation Kokoro has tokens for,
//        spaced as the source was.
//  IN:   KokoroPhonemizer.phonemizeUnits (after KokoroTextNormalizer)
//  OUT:  [Token] — word / mark / line break, each knowing whether a space
//        came before it
//  PIN:  Kokoro learned its pauses and intonation from misaki's phoneme
//        strings, which keep punctuation inline: "həlˈO, wˈɜɹld." — a mark
//        sits against the word before it and a space follows. The marks here
//        are exactly the vocab's: , . ! ? ; : … — ( ) “ ”
//

import Foundation

enum KokoroLexer {

    enum Lexeme: Equatable {
        case word(String)
        /// One of Kokoro's punctuation tokens.
        case mark(String)
        /// A line break: a boundary with no mark of its own. Two or more in a
        /// row (a blank line) are a paragraph.
        case lineBreak(paragraph: Bool)
    }

    struct Token: Equatable {
        var lexeme: Lexeme
        var spaceBefore: Bool
    }

    /// Marks the model pauses on.
    static let pausing: Set<String> = [",", ".", "!", "?", ";", ":", "…", "—"]
    /// Marks that end a sentence.
    static let terminal: Set<String> = [".", "!", "?", "…"]
    /// Marks that hug the word after them.
    static let opening: Set<String> = ["“", "("]
    /// Marks that hug the word before them and carry no pause of their own.
    static let closing: Set<String> = ["”", ")"]

    static func lex(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var quoteOpen = false
        var pendingSpace = false
        var pendingNewlines = 0
        var run = ""

        func emitRun() {
            guard !run.isEmpty else { return }
            if pendingNewlines > 0, !tokens.isEmpty {
                tokens.append(Token(lexeme: .lineBreak(paragraph: pendingNewlines > 1), spaceBefore: false))
            }
            let spaced = !tokens.isEmpty && (pendingSpace || pendingNewlines > 0)
            split(run, spaceBefore: spaced, quoteOpen: &quoteOpen, into: &tokens)
            run = ""
            pendingSpace = false
            pendingNewlines = 0
        }

        for character in prepared(text) {
            if character == "\n" {
                emitRun()
                pendingNewlines += 1
            } else if character.isWhitespace {
                emitRun()
                pendingSpace = true
            } else {
                run.append(character)
            }
        }
        emitRun()
        return tokens
    }

    // MARK: - Characters

    /// One spelling per mark: ellipses, dashes, guillemets, brackets and
    /// typographic spaces folded to what the vocab has.
    static func prepared(_ text: String) -> String {
        var s = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for space in ["\u{00A0}", "\u{202F}", "\u{2009}", "\u{2007}", "\t"] {
            s = s.replacingOccurrences(of: space, with: " ")
        }
        s = s.replacingOccurrences(of: #"\.{3,}"#, with: "…", options: .regularExpression)
        s = s.replacingOccurrences(of: "--", with: "—")
        for dash in ["\u{2013}", "\u{2015}", "\u{2012}"] {
            s = s.replacingOccurrences(of: dash, with: "—")
        }
        let folds: [(String, String)] = [
            ("«", "“"), ("»", "”"), ("„", "“"), ("‘", "'"), ("’", "'"), ("[", "("), ("]", ")"),
        ]
        for (from, to) in folds { s = s.replacingOccurrences(of: from, with: to) }
        return s
    }

    // MARK: - One whitespace-delimited run

    private static let leadingSet: Set<Character> = ["\"", "“", "(", "'", "—", "…", "-"]
    private static let trailingSet: Set<Character> = [".", ",", "!", "?", ";", ":", "…", "”", "\"", ")", "'", "—"]

    private static func split(_ run: String, spaceBefore: Bool, quoteOpen: inout Bool, into tokens: inout [Token]) {
        let chars = Array(run)
        var first = true
        func push(_ lexeme: Lexeme) {
            if case .mark(let mark) = lexeme, case .mark(let previous) = tokens.last?.lexeme,
               mark == previous, !first || !spaceBefore {
                return  // "!!" → "!"
            }
            tokens.append(Token(lexeme: lexeme, spaceBefore: first && spaceBefore))
            first = false
        }
        func pushMark(_ c: Character, leading: Bool) {
            switch c {
            case "\"":
                // Adjacency decides: a quote before the word opens, after it closes.
                let opens = leading
                quoteOpen = opens
                push(.mark(opens ? "“" : "”"))
            case "“": quoteOpen = true; push(.mark("“"))
            case "”": quoteOpen = false; push(.mark("”"))
            case "'": break  // an apostrophe at an edge is not a quote Kokoro has
            case "-": push(.mark("—"))
            default: push(.mark(String(c)))
            }
        }

        // A run with no letter or digit is all marks: "—", "-", "…", a lone quote.
        guard chars.contains(where: { $0.isLetter || $0.isNumber }) else {
            for c in chars {
                if c == "\"" {
                    pushMark(c, leading: !quoteOpen)
                } else if leadingSet.contains(c) || trailingSet.contains(c) {
                    pushMark(c, leading: false)
                }
            }
            return
        }

        var start = 0
        while start < chars.count, !chars[start].isLetter, !chars[start].isNumber, leadingSet.contains(chars[start]) {
            start += 1
        }
        var end = chars.count
        while end > start, !chars[end - 1].isLetter, !chars[end - 1].isNumber, trailingSet.contains(chars[end - 1]) {
            end -= 1
        }
        for c in chars[0..<start] where c != "-" { pushMark(c, leading: true) }

        // Inside the word: "word—word", "wait…what".
        var piece = ""
        for c in chars[start..<end] {
            if c == "—" || c == "…" {
                if !piece.isEmpty { push(.word(piece)); piece = "" }
                pushMark(c, leading: false)
            } else {
                piece.append(c)
            }
        }
        if !piece.isEmpty { push(.word(piece)) }

        for c in chars[end..<chars.count] { pushMark(c, leading: false) }
    }
}
