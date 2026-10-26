//
//  Slug.swift
//  AdverbCore
//
//  WHAT: Folder names from titles: lowercase kebab, ASCII, short.
//  PIN:  exFAT is case-insensitive: "Ambient" and "ambient" are one folder. Uniqueness is
//        checked case-insensitively, and slugs are lowercase so the question never arises.
//

import Foundation

public enum Slug {
    public static func make(_ title: String, maxLength: Int = 40) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var out = ""
        var lastDash = true
        for scalar in folded.unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                out.unicodeScalars.append(scalar); lastDash = false
            } else if !lastDash {
                out.append("-"); lastDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        if out.count > maxLength {
            out = String(out.prefix(maxLength))
            while out.hasSuffix("-") { out.removeLast() }
        }
        return out.isEmpty ? "untitled" : out
    }

    /// `make(title)`, or `make(title)-2`, `-3`… — the first not in `taken` (compared lowercased).
    public static func unique(_ title: String, taken: Set<String>, maxLength: Int = 40) -> String {
        let lowered = Set(taken.map { $0.lowercased() })
        let base = make(title, maxLength: maxLength)
        if !lowered.contains(base) { return base }
        var n = 2
        while lowered.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    /// A topic slug as the plan uses it in file names: kebab, at most 24 characters.
    public static func isTopicSlug(_ slug: String) -> Bool {
        !slug.isEmpty && slug.count <= 24 && make(slug, maxLength: 24) == slug
    }
}
