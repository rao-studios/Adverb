//
//  KokoroTextNormalizer.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: Unspeakable orthography → words before split. Pure tables + regex.
//  IN:   KokoroPhonemizer
//  OUT:  rewritten text + substitution pairs for PronunciationReport
//  PIN:  Pass order is load-bearing (money/times before bare cardinals).
//

import Foundation

struct KokoroTextNormalizer {

    /// Normalize `text`; returns the rewritten text plus (original, replacement)
    /// pairs for provenance in the PronunciationReport. `extended` adds the
    /// passes the legacy voice never had (emoji, email, URLs, dates, ranges,
    /// fractions, initialisms, symbols) — off, the output is byte-identical
    /// to what shipped.
    static func normalize(
        _ text: String, extended: Bool = false
    ) -> (text: String, substitutions: [(original: String, replacement: String)]) {
        var out = extended ? withoutEmoji(text) : text
        var subs: [(String, String)] = []

        let ordered = extended
            ? leadingPasses + passes[..<afterPhone] + middlePasses + passes[afterPhone...] + trailingPasses
            : passes
        for pass in ordered {
            out = apply(pass, to: out, recording: &subs)
        }
        return (out, subs)
    }

    /// Where the extended range and fraction passes go: after phone numbers
    /// (which own "415-555-1212"), before years and cardinals.
    private static let afterPhone = 6

    /// Pictographs a voice can't say; skin tones, joiners and variation selectors with them.
    static func withoutEmoji(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let pictograph = (0x1F000...0x1FAFF).contains(v) || (0x2600...0x27BF).contains(v)
                || (0x1F1E6...0x1F1FF).contains(v)
            let joiner = v == 0x200D || v == 0xFE0F || v == 0xFE0E || (0x1F3FB...0x1F3FF).contains(v)
            if !pictograph && !joiner { kept.append(scalar) }
        }
        return String(kept)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Pass machinery

    private struct Pass {
        let regex: NSRegularExpression
        /// Return nil to leave the match untouched.
        let replace: ([String]) -> String?
    }

    private static func apply(
        _ pass: Pass, to text: String,
        recording subs: inout [(String, String)]
    ) -> String {
        let matches = pass.regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }
        var result = text
        var newSubs: [(String, String)] = []
        for match in matches.reversed() {
            guard let full = Range(match.range, in: text) else { continue }
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                if let r = Range(match.range(at: i), in: text) {
                    groups.append(String(text[r]))
                } else {
                    groups.append("")
                }
            }
            guard let replacement = pass.replace(groups) else { continue }
            newSubs.append((groups[0], replacement))
            result = result.replacingCharacters(in: full, with: replacement)
        }
        // Matches were walked back-to-front; record them in reading order.
        subs.append(contentsOf: newSubs.reversed())
        return result
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure is programmer error.
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    // MARK: - The passes (order matters)

    private static let passes: [Pass] = [
        // 1. Currency: $5, $5.50, $1,200
        Pass(regex: regex(#"\$(\d{1,3}(?:,\d{3})*|\d+)(?:\.(\d{1,2}))?"#)) { g in
            let dollars = Int(g[1].replacingOccurrences(of: ",", with: "")) ?? 0
            var words = cardinal(dollars) + (dollars == 1 ? " dollar" : " dollars")
            if !g[2].isEmpty {
                let cents = Int(g[2].count == 1 ? g[2] + "0" : g[2]) ?? 0
                if cents > 0 {
                    words += " and " + cardinal(cents) + (cents == 1 ? " cent" : " cents")
                }
            }
            return words
        },
        // 2. Clock times with minutes: 3:30pm, 12:00, 9:05 AM
        Pass(regex: regex(#"\b(\d{1,2}):(\d{2})\s?([aApP])\.?[mM]\.?\b|\b(\d{1,2}):(\d{2})\b"#)) { g in
            let hourText = g[1].isEmpty ? g[4] : g[1]
            let minuteText = g[2].isEmpty ? g[5] : g[2]
            guard let hour = Int(hourText), let minute = Int(minuteText),
                  hour <= 24, minute <= 59 else { return nil }
            var words = cardinal(hour)
            if minute == 0 {
                words += g[3].isEmpty ? " o'clock" : ""
            } else if minute < 10 {
                words += " oh " + cardinal(minute)
            } else {
                words += " " + cardinal(minute)
            }
            if !g[3].isEmpty {
                words += " " + g[3].lowercased() + " m"
            }
            return words
        },
        // 3. Bare meridiem times: 3pm, 11 AM
        Pass(regex: regex(#"\b(\d{1,2})\s?([aApP])\.?[mM]\.?\b"#)) { g in
            guard let hour = Int(g[1]), hour <= 24 else { return nil }
            return cardinal(hour) + " " + g[2].lowercased() + " m"
        },
        // 4. Percent: 42%, 3.5%
        Pass(regex: regex(#"\b(\d+)(?:\.(\d+))?%"#)) { g in
            var words = cardinal(Int(g[1]) ?? 0)
            if !g[2].isEmpty {
                words += " point " + digitByDigit(g[2])
            }
            return words + " percent"
        },
        // 5. Ordinals: 1st, 2nd, 3rd, 11th
        Pass(regex: regex(#"\b(\d+)(st|nd|rd|th)\b"#)) { g in
            guard let n = Int(g[1]) else { return nil }
            return ordinal(n)
        },
        // 6. Phone-like digit runs (≥7 digits with separators): 415-555-1212
        Pass(regex: regex(#"\b\d(?:[\d\-\.]*\d)?\b"#)) { g in
            let digits = g[0].filter(\.isNumber)
            guard digits.count >= 7, g[0].contains(where: { $0 == "-" || $0 == "." }) else { return nil }
            return digitByDigit(String(digits))
        },
        // 7. Standalone years 1000–2999 (pair reading)
        Pass(regex: regex(#"\b([12]\d{3})\b"#)) { g in
            guard let year = Int(g[1]) else { return nil }
            return yearWords(year)
        },
        // 8. Decimals: 3.14
        Pass(regex: regex(#"\b(\d+)\.(\d+)\b"#)) { g in
            guard let whole = Int(g[1]) else { return nil }
            return cardinal(whole) + " point " + digitByDigit(g[2])
        },
        // 9. Comma-grouped and plain cardinals
        Pass(regex: regex(#"\b\d{1,3}(?:,\d{3})+\b|\b\d+\b"#)) { g in
            let digits = g[0].replacingOccurrences(of: ",", with: "")
            if digits.count > 15 { return digitByDigit(digits) }
            guard let n = Int(digits) else { return digitByDigit(digits) }
            return cardinal(n)
        },
        // 10. Abbreviations (context-aware where needed)
        Pass(regex: regex(#"\bDr\.\s+(?=[A-Z])"#)) { _ in "Doctor " },
        Pass(regex: regex(#"\bDr\.(?=\s|$)"#)) { _ in "Drive" },
        Pass(regex: regex(#"\bMr\.(?=\s)"#)) { _ in "Mister" },
        Pass(regex: regex(#"\bMrs\.(?=\s)"#)) { _ in "Missus" },
        Pass(regex: regex(#"\bMs\.(?=\s)"#)) { _ in "Miss" },
        Pass(regex: regex(#"\bSt\.\s+(?=[A-Z])"#)) { _ in "Saint " },
        Pass(regex: regex(#"\b[vV][sS]\.?(?=\s|$)"#)) { _ in "versus" },
        Pass(regex: regex(#"\be\.g\.(?=[\s,]|$)"#)) { _ in "for example" },
        Pass(regex: regex(#"\bi\.e\.(?=[\s,]|$)"#)) { _ in "that is" },
        Pass(regex: regex(#"\bNo\.\s?(?=\d)"#)) { _ in "number " },
        // 11. Units after a number word (cardinal pass already ran). Gate on known number words, not digits.
        Pass(regex: regex(
            #"\b(zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|trillion)\s(km|mi|kg|lb|lbs|GB|MB|TB|KB|GHz|MHz|ms|hr|hrs|min|mins|sec|secs|ft|mph)\b"#
        )) { g in
            guard let unit = unitNames[g[2]] else { return nil }
            return g[1] + " " + unit
        },
    ]

    private static let unitNames: [String: String] = [
        "km": "kilometers", "mi": "miles", "kg": "kilograms",
        "lb": "pounds", "lbs": "pounds",
        "GB": "gigabytes", "MB": "megabytes", "TB": "terabytes", "KB": "kilobytes",
        "GHz": "gigahertz", "MHz": "megahertz",
        "ms": "milliseconds", "hr": "hours", "hrs": "hours",
        "min": "minutes", "mins": "minutes", "sec": "seconds", "secs": "seconds",
        "ft": "feet", "mph": "miles per hour",
    ]

    // MARK: - Extended passes

    private static let months = [
        "January", "February", "March", "April", "May", "June", "July",
        "August", "September", "October", "November", "December",
    ]
    private static let monthAbbreviations: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8,
        "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    static func dateWords(month: Int, day: Int, year: Int?) -> String? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var words = months[month - 1] + " " + ordinal(day)
        if let year { words += ", " + yearWords(year) }
        return words
    }

    /// Before everything that reads digits: a date or an address is not a number.
    private static let leadingPasses: [Pass] = [
        // Email: ritesh@rao.nyc → ritesh at rao dot nyc
        Pass(regex: regex(#"\b([A-Za-z0-9._%+-]+)@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)\b"#)) { g in
            spokenAddress(g[1]) + " at " + spokenAddress(g[2])
        },
        // URL: the host, said; scheme, www and path left out.
        Pass(regex: regex(#"\b(?:https?://)?(?:www\.)?((?:[A-Za-z0-9-]+\.)+(?:com|org|net|io|ai|dev|app|co|nyc|edu|gov|me|us|uk|ca|de|fr|tv|so|xyz))\b(?:/[^\s]*[^\s.,;:!?)"”])?"#)) { g in
            spokenAddress(g[1].lowercased())
        },
        // ISO date: 2026-09-28
        Pass(regex: regex(#"\b([12]\d{3})-(\d{1,2})-(\d{1,2})\b"#)) { g in
            guard let y = Int(g[1]), let m = Int(g[2]), let d = Int(g[3]) else { return nil }
            return dateWords(month: m, day: d, year: y)
        },
        // US date with a year: 9/28/2026, 9/28/26
        Pass(regex: regex(#"\b(\d{1,2})/(\d{1,2})/(\d{2}|\d{4})\b"#)) { g in
            guard let m = Int(g[1]), let d = Int(g[2]), var y = Int(g[3]) else { return nil }
            if g[3].count == 2 { y += 2000 }
            return dateWords(month: m, day: d, year: y)
        },
        // Month and day: September 28, Sept. 28th, Oct 3
        Pass(regex: regex(#"\b(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec)\.? (\d{1,2})(?:st|nd|rd|th)?\b"#)) { g in
            let key = g[1].lowercased()
            let month = months.firstIndex { $0.lowercased() == key }.map { $0 + 1 } ?? monthAbbreviations[key]
            guard let month, let day = Int(g[2]) else { return nil }
            return dateWords(month: month, day: day, year: nil)
        },
    ]

    /// After phone numbers, before years and cardinals.
    private static let middlePasses: [Pass] = [
        // Ranges: 2019–2021, pages 10-12, 3 – 5 → "to"; the numbers are read later.
        Pass(regex: regex(#"\b(\d+)\s?[-–—]\s?(\d+)\b"#)) { g in
            "\(g[1]) to \(g[2])"
        },
        // Fractions: 1/2 one half, 3/4 three quarters, 2/3 two thirds, 24/7.
        Pass(regex: regex(#"\b(\d+)/(\d+)\b"#)) { g in
            guard let n = Int(g[1]), let d = Int(g[2]), d > 0 else { return nil }
            if n == 24 && d == 7 { return "twenty-four seven" }
            return fraction(n, d)
        },
    ]

    /// After abbreviations: letters and symbols.
    private static let trailingPasses: [Pass] = [
        // Dotted initialisms: U.S. → U S, a.m. without a number → A M.
        Pass(regex: regex(#"\b((?:[A-Za-z]\.){2,})"#)) { g in
            g[1].filter(\.isLetter).map { String($0).uppercased() }.joined(separator: " ")
        },
        Pass(regex: regex(#"½"#)) { _ in " one half" },
        Pass(regex: regex(#"¼"#)) { _ in " one quarter" },
        Pass(regex: regex(#"¾"#)) { _ in " three quarters" },
        Pass(regex: regex(#"⅓"#)) { _ in " one third" },
        Pass(regex: regex(#"⅔"#)) { _ in " two thirds" },
        Pass(regex: regex(#"\s?°\s?F\b"#)) { _ in " degrees Fahrenheit" },
        Pass(regex: regex(#"\s?°\s?C\b"#)) { _ in " degrees Celsius" },
        Pass(regex: regex(#"\s?°"#)) { _ in " degrees" },
        Pass(regex: regex(#"\s?&\s?"#)) { _ in " and " },
        Pass(regex: regex(#"(?<=\w)\s?\+\s?(?=\w)"#)) { _ in " plus " },
        Pass(regex: regex(#"\band/or\b"#)) { _ in "and or" },
        // "#1", its number already words: "#one" → "number one".
        Pass(regex: regex(#"#\s?(?=(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|a hundred)\b)"#)) { _ in "number " },
    ]

    /// Domain labels said letter by letter ("dot N Y C", not "dot nick").
    private static let spelledLabels: Set<String> = [
        "nyc", "io", "ai", "uk", "us", "tv", "de", "fr", "ca", "xyz", "edu", "gov", "co",
    ]

    /// "rao.nyc" → "rao dot N Y C"; "first.last" → "first dot last".
    static func spokenAddress(_ address: String) -> String {
        address
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { label -> String in
                let lower = label.lowercased()
                guard spelledLabels.contains(lower) else { return String(label) }
                return lower.uppercased().map(String.init).joined(separator: " ")
            }
            .joined(separator: " dot ")
            .replacingOccurrences(of: "_", with: " underscore ")
            .replacingOccurrences(of: "-", with: " dash ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func fraction(_ n: Int, _ d: Int) -> String {
        let named: [Int: (String, String)] = [
            2: ("half", "halves"), 3: ("third", "thirds"), 4: ("quarter", "quarters"),
        ]
        if let (one, many) = named[d] { return cardinal(n) + " " + (n == 1 ? one : many) }
        if d <= 10 { return cardinal(n) + " " + (n == 1 ? ordinal(d) : ordinal(d) + "s") }
        return cardinal(n) + " over " + cardinal(d)
    }

    // MARK: - Number words

    private static let ones = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen",
    ]
    private static let tens = [
        "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
    ]
    private static let scales: [(Int, String)] = [
        (1_000_000_000_000, "trillion"),
        (1_000_000_000, "billion"),
        (1_000_000, "million"),
        (1_000, "thousand"),
    ]

    /// 0…999,999,999,999,999 → English words.
    static func cardinal(_ n: Int) -> String {
        if n < 0 { return "minus " + cardinal(-n) }
        if n < 20 { return ones[n] }
        if n < 100 {
            let t = tens[n / 10]
            return n % 10 == 0 ? t : t + "-" + ones[n % 10]
        }
        if n < 1000 {
            let head = ones[n / 100] + " hundred"
            return n % 100 == 0 ? head : head + " " + cardinal(n % 100)
        }
        for (value, name) in scales where n >= value {
            let head = cardinal(n / value) + " " + name
            let rest = n % value
            return rest == 0 ? head : head + " " + cardinal(rest)
        }
        return ones[0]
    }

    /// 1st → first, 21st → twenty-first, 100th → one hundredth.
    static func ordinal(_ n: Int) -> String {
        let irregular: [Int: String] = [
            1: "first", 2: "second", 3: "third", 5: "fifth", 8: "eighth",
            9: "ninth", 12: "twelfth",
        ]
        if let word = irregular[n] { return word }
        if n < 20 { return ones[n] + "th" }
        let base = cardinal(n)
        // twenty → twentieth, thirty-one → thirty-first, etc.
        if n % 10 == 0, n < 100 { return String(base.dropLast()) + "ieth" }
        if n % 100 != 0, let lastDash = base.lastIndex(of: "-") {
            let prefix = base[..<lastDash]
            let tail = Int(String(n).suffix(1)) ?? 0
            return prefix + "-" + ordinal(tail)
        }
        if n % 100 != 0, n % 100 < 20 {
            let parts = base.components(separatedBy: " ")
            let tail = ordinal(n % 100)
            return parts.dropLast().joined(separator: " ") + " " + tail
        }
        return base + "th"
    }

    /// Year pair-reading: 2026 → "twenty twenty-six", 2007 → "two thousand seven",
    /// 1900 → "nineteen hundred", 2000 → "two thousand".
    static func yearWords(_ year: Int) -> String {
        let high = year / 100
        let low = year % 100
        if year == 2000 { return "two thousand" }
        if (2001...2009).contains(year) { return "two thousand " + ones[low] }
        if low == 0 { return cardinal(high) + " hundred" }
        if low < 10 { return cardinal(high) + " oh " + ones[low] }
        return cardinal(high) + " " + cardinal(low)
    }

    /// "1212" → "one two one two".
    static func digitByDigit(_ digits: String) -> String {
        digits.compactMap { $0.wholeNumberValue.map { ones[$0] } }.joined(separator: " ")
    }
}
