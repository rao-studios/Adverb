//
//  KokoroSpeechPlan.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: Where a text is cut into model calls, and the silence each cut gets.
//        Kokoro has no SSML and no speed input: inside a call its pauses come
//        from punctuation tokens; between calls they are these.
//  IN:   KokoroPhonemes (KokoroPhonemizer+Units)
//  OUT:  [KokoroSegment] for KokoroEngine+Render; KokoroPause for the speaker's
//        gap between chunks (ChunkPolicy.pausesBetweenChunks)
//  PIN:  Nothing is ever truncated. A cut prefers a sentence end, then ; : ,
//        and dashes, then just before a conjunction, then any word; the pieces
//        are balanced rather than filled greedily, so no tiny tail is left.
//  PIN:  A line break always cuts: a heading, a list item and a paragraph
//        each get their own pause.
//

import Foundation

/// A designed silence between two pieces of speech, voiced edge to voiced edge.
public enum KokoroPause: String, Sendable, Equatable, CaseIterable {
    case none, word, clause, sentence, line, paragraph

    /// Set against the model's own, measured in its audio (2026-09-28, af_heart):
    /// inside a call a comma leaves 40–85 ms of silence and a sentence end
    /// 225–565 ms. A cut should sound like the boundary it replaced.
    public var milliseconds: Int {
        switch self {
        case .none: return 0
        case .word: return 40
        case .clause: return 120
        case .sentence: return 350
        case .line: return 330
        case .paragraph: return 600
        }
    }

    public var seconds: Double { Double(milliseconds) / 1000 }
}

/// One model call's worth of a text.
struct KokoroSegment: Equatable {
    /// Units of the KokoroPhonemes it was cut from.
    var range: Range<Int>
    /// Appended when the piece ends on a word ("." at an end; "," before a conjunction).
    var closeWith: String?
    var pauseAfter: KokoroPause
}

enum KokoroSegmenter {

    /// Content tokens per call (BOS/EOS aside). Under the window's 240, so a
    /// piece this long still fits the 15 s audio grid at a slow pace.
    static let budget = 200

    /// Cut before these when nothing better is in reach.
    static let conjunctions: Set<String> = [
        "and", "but", "or", "nor", "so", "yet", "because", "which", "that", "while", "although",
        "though", "if", "when", "where", "who", "whose", "then", "until", "unless", "since",
        "before", "after", "whereas",
    ]

    static func plan(_ phonemes: KokoroPhonemes, budget: Int = budget) -> [KokoroSegment] {
        let units = phonemes.units
        var segments: [KokoroSegment] = []
        var blockStart = 0
        for index in units.indices {
            guard case .lineBreak(let paragraph) = units[index].kind else { continue }
            segments += split(phonemes, blockStart..<index, budget: budget,
                              pauseAfter: paragraph ? .paragraph : .line)
            blockStart = index + 1
        }
        segments += split(phonemes, blockStart..<units.count, budget: budget, pauseAfter: .none)
        return segments.filter { !phonemes.ids($0.range, closeWith: $0.closeWith).isEmpty }
    }

    /// One block (no line breaks), cut until every piece fits.
    static func split(
        _ phonemes: KokoroPhonemes, _ block: Range<Int>, budget: Int, pauseAfter: KokoroPause
    ) -> [KokoroSegment] {
        guard !block.isEmpty else { return [] }
        let units = phonemes.units
        var pieces: [KokoroSegment] = []
        var start = block.lowerBound
        while start < block.upperBound {
            let rest = start..<block.upperBound
            let restCost = phonemes.ids(rest, closeWith: ".").count
            if restCost <= budget {
                pieces.append(KokoroSegment(range: rest, closeWith: ".", pauseAfter: pauseAfter))
                break
            }
            let count = (restCost + budget - 1) / budget
            let target = Double(restCost) / Double(count)

            var best: (cut: Int, tier: Int, distance: Double)?
            var longest: (cut: Int, tier: Int)?
            for cut in (start + 1)..<block.upperBound {
                guard let tier = tier(units, cut: cut) else { continue }
                let cost = phonemes.ids(start..<cut, closeWith: closing(tier)).count
                if cost > budget { break }
                longest = (cut, tier)
                guard Double(cost) >= 0.55 * target else { continue }
                let distance = abs(Double(cost) - target)
                if best == nil || tier < best!.tier || (tier == best!.tier && distance < best!.distance) {
                    best = (cut, tier, distance)
                }
            }
            // Nothing in the balanced window: the longest piece that fits; a
            // single unit past the budget goes alone rather than be dropped.
            let chosen = best.map { ($0.cut, $0.tier) } ?? longest ?? (start + 1, 4)
            pieces.append(KokoroSegment(
                range: start..<chosen.0, closeWith: closing(chosen.1), pauseAfter: pause(chosen.1)))
            start = chosen.0
        }
        return pieces
    }

    /// How good a cut before `units[cut]` is: 0 sentence end, 1 `; :`, 2 `, —`,
    /// 3 before a conjunction or an opening mark, 4 between words. Nil: never here.
    static func tier(_ units: [KokoroPhonemes.Unit], cut: Int) -> Int? {
        let previous = units[cut - 1]
        let next = units[cut]
        if let mark = next.mark, KokoroLexer.closing.contains(mark) || !KokoroLexer.opening.contains(mark) {
            return nil  // a mark stays with the word before it
        }
        if let mark = previous.mark {
            if KokoroLexer.opening.contains(mark) { return nil }
            var effective = mark
            if KokoroLexer.closing.contains(mark) {
                // `.”` ends as the `.` inside it did.
                effective = units[..<(cut - 1)].last(where: { $0.mark.map { !KokoroLexer.closing.contains($0) } ?? true })?.mark ?? ""
            }
            if KokoroLexer.terminal.contains(effective) { return 0 }
            if effective == ";" || effective == ":" { return 1 }
            if effective == "," || effective == "—" { return 2 }
            return 3
        }
        if let mark = next.mark, KokoroLexer.opening.contains(mark) { return 3 }
        if case .word(let word) = next.kind, conjunctions.contains(word.lowercased()) { return 3 }
        return 4
    }

    static func closing(_ tier: Int) -> String? {
        switch tier {
        case 3: return ","
        default: return nil
        }
    }

    static func pause(_ tier: Int) -> KokoroPause {
        switch tier {
        case 0: return .sentence
        case 1, 2, 3: return .clause
        default: return .word
        }
    }
}
