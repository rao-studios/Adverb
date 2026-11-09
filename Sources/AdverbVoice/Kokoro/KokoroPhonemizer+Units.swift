//
//  KokoroPhonemizer+Units.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: Text → words, marks and line breaks, each with its own token ids,
//        so a piece of it can be spoken without cutting a word or losing a
//        pause. The function words whose sound depends on what follows are
//        settled here too.
//  IN:   KokoroPhonemizer.phonemize (options.punctuation), KokoroEngine+Render
//  OUT:  KokoroPhonemes — ids(range) assembles any run of units, spaced as
//        the source was
//  PIN:  Word resolution is the same ladder as the legacy path, in the same
//        order, with the same POS alignment and provenance.
//

import Foundation

/// One text, phonemized unit by unit.
struct KokoroPhonemes {

    struct Unit: Equatable {
        enum Kind: Equatable {
            case word(String)
            case mark(String)
            case lineBreak(paragraph: Bool)
        }
        var kind: Kind
        /// The unit's own tokens: a word's phonemes, a mark's one id, none for a line break.
        var ids: [Int32]
        var spaceBefore: Bool

        var isWord: Bool { if case .word = kind { return true } else { return false } }
        var mark: String? { if case .mark(let mark) = kind { return mark } else { return nil } }
    }

    var units: [Unit]
    var report: PronunciationReport
    let spaceID: Int32?
    let markIDs: [String: Int32]
    let symbols: [Int32: String]

    /// Token ids for `units[range]`: spaces where the source had them, a line
    /// break closed with "." when nothing else closes it, and `closeWith`
    /// appended when the range ends on a word.
    func ids(_ range: Range<Int>, closeWith: String?) -> [Int32] {
        var out: [Int32] = []
        var lastWasWord = false
        func space() {
            if let spaceID, !out.isEmpty, out.last != spaceID { out.append(spaceID) }
        }
        for unit in units[range] {
            switch unit.kind {
            case .word:
                guard !unit.ids.isEmpty else { continue }
                if unit.spaceBefore { space() }
                out.append(contentsOf: unit.ids)
                lastWasWord = true
            case .mark:
                guard let id = unit.ids.first else { continue }
                if unit.spaceBefore { space() }
                out.append(id)
                lastWasWord = false
            case .lineBreak:
                if lastWasWord, let period = markIDs["."] { out.append(period) }
                lastWasWord = false
            }
        }
        if lastWasWord, let closeWith, let id = markIDs[closeWith] { out.append(id) }
        if let spaceID, out.last == spaceID { out.removeLast() }
        return out
    }

    /// The ids as the model's alphabet, for traces.
    func render(_ ids: [Int32]) -> String {
        ids.map { symbols[$0] ?? "" }.joined()
    }
}

extension KokoroPhonemizer {

    /// `text` as units. Marks without a vocab id are dropped silently (none
    /// should exist: the lexer emits only the vocab's).
    func phonemizeUnits(_ text: String, options: KokoroOptions) async -> KokoroPhonemes {
        let (cleanText, ssmlOverrides) = preprocessSSML(text)
        let (normalized, substitutions) = KokoroTextNormalizer.normalize(cleanText, extended: true)
        let tokens = KokoroLexer.lex(normalized)
        let words: [String] = tokens.compactMap {
            if case .word(let word) = $0.lexeme { return word } else { return nil }
        }

        var report = PronunciationReport(text: text, normalizedText: normalized)
        var originQueue = OriginQueue(substitutions: substitutions)
        let posTags: [String?] = words.contains(where: { variantLexicon[$0.lowercased()] != nil })
            ? Self.lexicalClasses(for: normalized, alignedWith: words)
            : Array(repeating: nil, count: words.count)

        var entries: [WordPronunciation] = []
        for (index, word) in words.enumerated() {
            var entry = await resolve(word, ssmlOverrides: ssmlOverrides, posTag: posTags[index])
            entry.original = originQueue.originFor(word: word)
            entries.append(entry)
        }
        if options.contextualFunctionWords {
            Self.applyContext(to: &entries, tokens: tokens)
        }

        var unmapped: Set<String> = []
        var units: [KokoroPhonemes.Unit] = []
        var wordIndex = 0
        for token in tokens {
            switch token.lexeme {
            case .word(let word):
                let ids = entries[wordIndex].ipa.isEmpty
                    ? [] : tokenIDs(forIPA: entries[wordIndex].ipa, unmapped: &unmapped)
                entries[wordIndex].tokenCount = ids.count
                units.append(.init(kind: .word(word), ids: ids, spaceBefore: token.spaceBefore))
                wordIndex += 1
            case .mark(let mark):
                guard let id = vocab[mark] else { continue }
                units.append(.init(kind: .mark(mark), ids: [Int32(id)], spaceBefore: token.spaceBefore))
            case .lineBreak(let paragraph):
                units.append(.init(kind: .lineBreak(paragraph: paragraph), ids: [], spaceBefore: false))
            }
        }
        report.words = entries
        report.unmappedScalars = unmapped.sorted()

        var markIDs: [String: Int32] = [:]
        for mark in KokoroLexer.pausing.union(KokoroLexer.opening).union(KokoroLexer.closing) {
            if let id = vocab[mark] { markIDs[mark] = Int32(id) }
        }
        var symbols: [Int32: String] = [:]
        for (symbol, id) in vocab { symbols[Int32(id)] = symbol }
        return KokoroPhonemes(
            units: units, report: report, spaceID: spaceTokenID(), markIDs: markIDs, symbols: symbols)
    }

    // MARK: - Function words

    /// misaki's vowel phonemes (Kokoro's notation: A I O Q W Y are diphthongs).
    static let vowels: Set<Character> = Set("AIOQWYaiuæɑɒɔəɛɜɪʊʌᵻ")

    /// Whether `ipa` starts on a vowel sound, stress marks skipped.
    static func startsWithVowel(_ ipa: String) -> Bool? {
        guard let first = ipa.first(where: { !"ˈˌː".contains($0) }) else { return nil }
        return vowels.contains(first)
    }

    /// Backward over the words, as misaki does: each word's sound may depend
    /// on the next word's first sound, or on there being no next word before
    /// a pause. Only dictionary sounds are touched — never a custom or inline one.
    static func applyContext(to entries: inout [WordPronunciation], tokens: [KokoroLexer.Token]) {
        // For each word, what follows it: the next word's index, or nil when a pause comes first.
        var following: [Int?] = []
        var wordIndex = 0
        for (position, token) in tokens.enumerated() {
            guard case .word = token.lexeme else { continue }
            var next: Int? = nil
            scan: for later in tokens[(position + 1)...] {
                switch later.lexeme {
                case .word:
                    next = wordIndex + 1
                    break scan
                case .mark(let mark) where KokoroLexer.opening.contains(mark) || KokoroLexer.closing.contains(mark):
                    continue
                default:
                    break scan
                }
            }
            following.append(next)
            wordIndex += 1
        }

        for index in entries.indices.reversed() {
            let entry = entries[index]
            guard [.lexicon, .lexiconVariant, .cache].contains(entry.source) else { continue }
            let futureVowel = following[index].flatMap { startsWithVowel(entries[$0].ipa) }
            let followed = following[index] != nil
            guard let ipa = contextual(entry.word, current: entry.ipa, futureVowel: futureVowel, followed: followed),
                  ipa != entry.ipa else { continue }
            entries[index].ipa = ipa
            entries[index].detail = "contextual"
        }
    }

    /// misaki's special cases (`get_special_case`) for the words a sentence
    /// leans on. `followed` is false before a pause or at the end.
    static func contextual(_ word: String, current: String, futureVowel: Bool?, followed: Bool) -> String? {
        switch word {
        case "the", "The":
            return futureVowel == true ? "ði" : "ðə"
        case "a":
            return "ɐ"
        case "A":
            // "A cup" is the article; "Plan A." is the letter.
            return followed ? "ɐ" : nil
        case "an", "An":
            return "ɐn"
        case "am":
            return followed ? "ɐm" : nil
        case "to", "To":
            guard followed, let futureVowel else { return nil }
            return futureVowel ? "tʊ" : "tə"
        case "in", "In":
            return followed ? "ɪn" : "ˈɪn"
        case "I":
            return "ˌI"
        default:
            return nil
        }
    }
}
