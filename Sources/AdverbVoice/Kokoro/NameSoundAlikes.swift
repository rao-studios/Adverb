//
//  NameSoundAlikes.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: Pure "heard as" engine — spellings a recognizer may write for her name.
//  IN:   KokoroEngine.nameHelp (Kokoro-notation IPA + the loaded lexicon)
//  OUT:  [Candidate] → Settings Name card → wake-word aliases
//  PIN:  Deterministic and local. The lexicon is injected; tests pass a tiny one.
//

import Foundation

public enum NameSoundAlikes {

    public struct Candidate: Sendable, Hashable {
        public enum Reason: String, Sendable {
            /// A lexicon word that sounds the same ("Merry" for "Mary").
            case homophone
            /// Two lexicon words that together sound the same ("Shiv on").
            case split
            /// A phonetic spelling of the same sound ("Shivon").
            case respelling
            /// A lexicon word one sound away.
            case nearMatch
        }

        public var spelling: String
        public var reason: Reason
        /// Everyday English — "Hey <word>" in ordinary speech will wake her too.
        public var isDictionaryWord: Bool

        public init(spelling: String, reason: Reason, isDictionaryWord: Bool) {
            self.spelling = spelling
            self.reason = reason
            self.isDictionaryWord = isDictionaryWord
        }
    }

    /// One word of the name and its pronunciation. Empty `ipa` = unknown; the
    /// word is kept as typed.
    public struct Token: Sendable, Equatable {
        public var word: String
        public var ipa: String

        public init(word: String, ipa: String) {
            self.word = word
            self.ipa = ipa
        }
    }

    // MARK: - Sound keys

    /// How a pronunciation *sounds*: stress and length dropped, reduced vowels
    /// and the flap folded into their plain phonemes.
    static func key(_ ipa: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in ipa.unicodeScalars {
            switch scalar {
            case "ˈ", "ˌ", "ː", " ", "-", "ʔ": continue
            case "ᵊ": out.append("ə")
            case "ᵻ": out.append("ɪ")
            case "ɾ": out.append("t")
            case "ɚ": out.append(contentsOf: "əɹ".unicodeScalars)
            case "ɝ": out.append(contentsOf: "ɜɹ".unicodeScalars)
            default: out.append(scalar)
            }
        }
        return String(out)
    }

    /// The lexicon turned around: sound → spellings.
    public struct Index: Sendable {
        /// key → spellings, plain words before proper nouns, shortest first.
        let byKey: [String: [String]]
        /// scalar count → keys, for near-match scans.
        let keysByLength: [Int: [String]]
        /// lowercased spelling → key.
        let keyByWord: [String: String]
        /// Lowercase lexicon entries — everyday words, not proper nouns.
        let plainWords: Set<String>

        public init(lexicon: [String: String]) {
            var byKey: [String: [String]] = [:]
            var keyByWord: [String: String] = [:]
            var plainWords = Set<String>()
            for (word, ipa) in lexicon where word.count >= 2 && word.allSatisfy(\.isLetter) {
                let key = NameSoundAlikes.key(ipa)
                guard !key.isEmpty else { continue }
                byKey[key, default: []].append(word)
                let lower = word.lowercased()
                // A plain entry's sound wins over a proper noun's.
                if keyByWord[lower] == nil || word == lower { keyByWord[lower] = key }
                if word == lower { plainWords.insert(word) }
            }
            for key in byKey.keys {
                byKey[key]?.sort { lhs, rhs in
                    let lhsPlain = lhs == lhs.lowercased(), rhsPlain = rhs == rhs.lowercased()
                    if lhsPlain != rhsPlain { return lhsPlain }
                    if lhs.count != rhs.count { return lhs.count < rhs.count }
                    return lhs < rhs
                }
            }
            self.byKey = byKey
            self.keyByWord = keyByWord
            self.plainWords = plainWords
            self.keysByLength = Dictionary(grouping: byKey.keys, by: { $0.unicodeScalars.count })
                .mapValues { $0.sorted() }
        }
    }

    // MARK: - Suggest

    /// Per-reason quotas, in rank order. Near matches last: a different sound.
    static let quotas: [(Candidate.Reason, Int)] =
        [(.homophone, 3), (.split, 2), (.respelling, 3), (.nearMatch, 2)]

    public static func suggest(
        name: String, tokens: [Token], index: Index, limit: Int = 8
    ) -> [Candidate] {
        let known = tokens.filter { !$0.ipa.isEmpty }
        guard !known.isEmpty else { return [] }
        let wholeKey = tokens.allSatisfy({ !$0.ipa.isEmpty })
            ? tokens.map { key($0.ipa) }.joined()
            : nil

        var pools: [Candidate.Reason: [Candidate]] = [:]
        if let wholeKey {
            pools[.homophone] = (index.byKey[wholeKey] ?? []).map {
                Candidate(spelling: display($0), reason: .homophone,
                          isDictionaryWord: index.plainWords.contains($0))
            }
            pools[.split] = splits(of: wholeKey, index: index).map {
                Candidate(spelling: $0.spelling, reason: .split, isDictionaryWord: $0.isEveryday)
            }
            if tokens.count == 1 {
                pools[.nearMatch] = nearMatches(of: wholeKey, index: index).map {
                    Candidate(spelling: display($0), reason: .nearMatch,
                              isDictionaryWord: index.plainWords.contains($0))
                }
            }
        }
        pools[.respelling] = respellings(of: tokens, index: index).map {
            Candidate(spelling: $0.spelling, reason: .respelling, isDictionaryWord: $0.isWord)
        }

        var seen: Set<String> = [WakePlanner.tokens(name).joined(separator: " ")]
        var result: [Candidate] = []
        for (reason, quota) in quotas {
            var taken = 0
            for candidate in pools[reason] ?? [] where taken < quota && result.count < limit {
                let normalized = WakePlanner.tokens(candidate.spelling).joined(separator: " ")
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                result.append(candidate)
                taken += 1
            }
        }
        return result
    }

    private static func display(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }

    // MARK: - Splits

    /// Two lexicon words that together make the sound, most balanced first.
    static func splits(of key: String, index: Index) -> [(spelling: String, isEveryday: Bool)] {
        let scalars = Array(key.unicodeScalars)
        guard scalars.count >= 4 else { return [] }
        var found: [(spelling: String, isEveryday: Bool, imbalance: Int)] = []
        for cut in 2...(scalars.count - 2) {
            let left = String(String.UnicodeScalarView(scalars[..<cut]))
            let right = String(String.UnicodeScalarView(scalars[cut...]))
            guard let first = index.byKey[left]?.first,
                  let second = index.byKey[right]?.first
            else { continue }
            found.append((
                "\(display(first)) \(second.lowercased())",
                index.plainWords.contains(first) && index.plainWords.contains(second),
                abs(cut * 2 - scalars.count)))
        }
        return found.sorted { $0.imbalance < $1.imbalance }.map { ($0.spelling, $0.isEveryday) }
    }

    // MARK: - Near matches

    /// Sounds a transcriber mixes up — the only swaps a near match may make.
    private static let confusable: [Set<Unicode.Scalar>] = [
        ["ɑ", "ɔ", "ʌ", "ə"], ["ɪ", "ə", "ɛ"], ["i", "ɪ"], ["u", "ʊ"], ["æ", "ɛ"],
        ["A", "ɛ"], ["O", "ɔ"], ["m", "n"], ["t", "d"], ["s", "z"], ["f", "θ"], ["v", "ð"],
    ]

    /// Lexicon words one confusable sound away, never at the first sound —
    /// change how a name starts and it is a different name. Short keys are
    /// skipped: at three sounds, one away is a different word.
    static func nearMatches(of key: String, index: Index) -> [String] {
        let phones = Array(key.unicodeScalars)
        guard phones.count >= 4 else { return [] }
        var found: [String] = []
        for candidate in index.keysByLength[phones.count] ?? [] {
            let other = Array(candidate.unicodeScalars)
            guard other[0] == phones[0] else { continue }
            let differing = phones.indices.filter { phones[$0] != other[$0] }
            guard differing.count == 1, let at = differing.first,
                  confusable.contains(where: { $0.contains(phones[at]) && $0.contains(other[at]) }),
                  let word = index.byKey[candidate]?.first
            else { continue }
            found.append(word)
        }
        return found.sorted { $0.count != $1.count ? $0.count < $1.count : $0 < $1 }
    }

    // MARK: - Respellings

    /// Phonetic spellings, one word varied at a time. A spelling that is a real
    /// word with a *different* sound is dropped — the recognizer writes that
    /// word only when it hears that sound.
    static func respellings(
        of tokens: [Token], index: Index
    ) -> [(spelling: String, isWord: Bool)] {
        var ranked: [(spelling: String, isWord: Bool, score: Double)] = []
        for (position, token) in tokens.enumerated() where !token.ipa.isEmpty {
            let tokenKey = key(token.ipa)
            for (spelling, score) in respell(tokenKey) {
                guard spelling != token.word.lowercased() else { continue }
                let wordKey = index.keyByWord[spelling]
                if let wordKey, wordKey != tokenKey { continue }
                var words = tokens.map(\.word)
                words[position] = display(spelling)
                ranked.append((words.joined(separator: " "), index.plainWords.contains(spelling), score))
            }
        }
        // Ties keep their order: earlier words first, then the beam's own order.
        return ranked.enumerated()
            .sorted { $0.element.score != $1.element.score
                ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map { ($0.element.spelling, $0.element.isWord) }
    }

    /// Weight by an option's rank in its grapheme list.
    private static let rankWeights: [Double] = [1.0, 0.55, 0.35, 0.25]
    private static let beamWidth = 48

    /// Best-first phonetic spellings of a sound key; empty when a sound has no rule.
    static func respell(_ key: String, limit: Int = 6) -> [(String, Double)] {
        let phones = Array(key.unicodeScalars)
        guard !phones.isEmpty else { return [] }
        var beam: [(text: String, score: Double)] = [("", 1)]
        for (position, phone) in phones.enumerated() {
            let previous = position > 0 ? phones[position - 1] : nil
            let next = position + 1 < phones.count ? phones[position + 1] : nil
            var options = graphemes(for: phone, next: next)
            // Doubled consonants only between two vowels ("merry"), never
            // at the edges or against another consonant ("niamm", "jorrvas").
            let betweenVowels = previous.map(vowels.contains) == true
                && next.map(vowels.contains) == true
            if !betweenVowels { options.removeAll(where: isDoubledConsonant) }
            guard !options.isEmpty else { return [] }
            var grown: [(text: String, score: Double)] = []
            for (text, score) in beam {
                for (rank, option) in options.enumerated() {
                    grown.append((text + option,
                                  score * rankWeights[min(rank, rankWeights.count - 1)]))
                }
            }
            grown.sort { $0.score != $1.score ? $0.score > $1.score : $0.text < $1.text }
            beam = Array(grown.prefix(beamWidth))
        }
        var seen = Set<String>()
        return beam.filter { $0.text.count >= 2 && seen.insert($0.text).inserted }
            .prefix(limit)
            .map { ($0.text, $0.score) }
    }

    /// "nn", "rr" — not the vowel digraphs "ee" and "oo".
    private static func isDoubledConsonant(_ grapheme: String) -> Bool {
        guard grapheme.count == 2, let letter = grapheme.first else { return false }
        return grapheme.last == letter && !"aeiouy".contains(letter)
    }

    private static let frontVowels: Set<Unicode.Scalar> = ["i", "ɪ", "ɛ", "A", "I"]
    private static let vowels: Set<Unicode.Scalar> =
        ["A", "I", "O", "W", "Y", "i", "u", "æ", "ɑ", "ɔ", "ə", "ɛ", "ɜ", "ɪ", "ʊ", "ʌ"]

    /// Common English spellings for one Kokoro phoneme, likeliest first.
    static func graphemes(for phone: Unicode.Scalar, next: Unicode.Scalar?) -> [String] {
        let final = next == nil
        let beforeFront = next.map { frontVowels.contains($0) } ?? false
        let beforeR = next == "ɹ"
        switch phone {
        // Vowels and diphthongs (Kokoro: A=eɪ, I=aɪ, O=oʊ, W=aʊ, Y=ɔɪ).
        case "A": return final ? ["ay", "ey", "ae"] : ["ay", "a", "ai", "ei"]
        case "I": return final ? ["y", "ie", "i"] : ["i", "y", "igh"]
        case "O": return final ? ["o", "oe", "ow"] : ["o", "oa", "ow"]
        case "W": return ["ow", "ou"]
        case "Y": return ["oy", "oi"]
        case "i": return final ? ["y", "ee", "ie", "i"] : ["ee", "i", "ea", "ie"]
        case "u": return final ? ["oo", "ew", "ou"] : ["oo", "u", "ew"]
        case "æ": return ["a"]
        case "ɑ": return final ? ["ah", "a"] : beforeR ? ["a", "ah"] : ["o", "a", "ah"]
        case "ɔ": return final ? ["aw", "a"] : beforeR ? ["o", "ou"] : ["o", "au", "aw"]
        case "ə": return final ? ["a", "ah"] : ["a", "e", "i", "o", "u"]
        case "ɛ": return ["e", "ea", "ai"]
        case "ɜ": return ["e", "u", "i"]
        case "ɪ": return ["i", "y"]
        case "ʊ": return ["oo", "u"]
        case "ʌ": return ["u", "o"]
        // Consonants.
        case "b": return ["b"]
        case "d": return ["d"]
        case "f": return ["f", "ph", "ff"]
        case "h": return ["h"]
        case "j": return ["y"]
        case "k": return beforeFront ? ["k"] : ["k", "c"]
        case "l": return ["l", "ll"]
        case "m": return ["m", "mm"]
        case "n": return ["n", "nn"]
        case "p": return ["p"]
        case "s": return beforeFront ? ["s", "c"] : ["s", "ss"]
        case "t": return ["t", "tt"]
        case "v": return ["v"]
        case "w": return ["w"]
        case "z": return ["z", "s"]
        case "ð", "θ": return ["th"]
        case "ŋ": return ["ng"]
        case "ɡ", "g": return ["g"]
        case "ɹ": return ["r", "rr"]
        case "ʃ": return ["sh", "ch"]
        case "ʒ": return ["zh", "s", "j"]
        case "ʤ": return beforeFront ? ["j", "g"] : ["j"]
        case "ʧ": return ["ch", "tch"]
        default: return []
        }
    }
}

/// What the Settings pronunciation-help button shows for a name.
public struct NamePronunciationHelp: Sendable {
    public struct Word: Sendable, Equatable {
        public var word: String
        /// Kokoro IPA; empty when nothing resolved.
        public var ipa: String
        public var source: PronunciationSource
    }

    public var name: String
    public var words: [Word]
    public var heardAs: [NameSoundAlikes.Candidate]
}
