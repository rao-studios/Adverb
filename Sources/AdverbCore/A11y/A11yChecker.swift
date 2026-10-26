//
//  A11yChecker.swift
//  AdverbCore
//
//  WHAT: Whether an asset's accessibility files say what the asset says: every headline, kicker
//        and chip string of the page appears in the captions; every scene has a description; the
//        alt text exists and fits each platform the day posts to; no cue flashes by.
//

import Foundation

public enum A11yChecker {
    /// Strings worth a caption, from the page's own markup: headlines, the kicker, chips.
    public static func pageStrings(html: String) -> [String] {
        var out: [String] = []
        let patterns = [#"class="head"[^>]*>(.*?)</div>"#, #"class="chip"[^>]*>(.*?)</span>\s*(?:</div>|<)"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard let r = Range(match.range(at: 1), in: html) else { continue }
                let text = String(html[r]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { out.append(text) }
            }
        }
        return out
    }

    /// Share of `strings` found (normalised, case-insensitively) in the cues.
    public static func coverage(of strings: [String], in cues: [Cue]) -> Double {
        guard !strings.isEmpty else { return 1 }
        let haystack = normalise(cues.map(\.text).joined(separator: " "))
        let found = strings.filter { haystack.contains(normalise($0)) }
        return Double(found.count) / Double(strings.count)
    }

    public static func check(captions: [Orientation: [Cue]], descriptions: [Cue], scenes: [Double], duration: Double,
                             altText: String, platforms: [Platform], pageStrings: [String]) -> [A11yCheck] {
        var checks: [A11yCheck] = []
        for (o, cues) in captions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let c = coverage(of: pageStrings, in: cues)
            if cues.isEmpty { checks.append(.init(.problem, "\(o.title) captions are empty.")) }
            else if c < 0.999 { checks.append(.init(.warning, String(format: "%@ captions cover %.0f%% of the on-screen headlines and chips.", o.title, c * 100))) }
            if let short = cues.first(where: { $0.end - $0.start < CueTracker.minDuration - 1e-6 && $0.kind == .text }) {
                checks.append(.init(.warning, String(format: "A %@ cue at %.1f s is under half a second.", o.rawValue, short.start)))
            }
        }
        let starts = scenes.isEmpty ? [0] : scenes.filter { $0 < duration - 0.5 }
        let undescribed = starts.filter { s in !descriptions.contains { $0.start <= s + 0.6 && $0.end > s } }
        if descriptions.isEmpty { checks.append(.init(.problem, "No descriptions track.")) }
        else if !undescribed.isEmpty { checks.append(.init(.warning, "\(undescribed.count) scene\(undescribed.count == 1 ? " has" : "s have") no description.")) }
        if altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { checks.append(.init(.problem, "No alt text.")) }
        for p in platforms {
            if let max = PlatformLimits.altTextMax(p), altText.count > max {
                checks.append(.init(.warning, "Alt text is \(altText.count) characters; \(p.title) takes \(max)."))
            }
        }
        if checks.isEmpty { checks.append(.init(.ok, "Captions cover the on-screen text; every scene is described; alt text fits.")) }
        return checks
    }

    static func normalise(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
}
