//
//  SkillText.swift
//  AdverbCore
//
//  WHAT: The skill as the writer reads it: rao-motion-assets without what Adverb does itself —
//        the render script (§5's render.py), the contact sheet recipe (§8) and the delivery
//        message (§9) — about three thousand tokens a call the model never needs.
//  PIN:  Cut by heading, so an edited skill (Settings' skillPath) is trimmed the same way; a
//        heading that is not there cuts nothing.
//

import Foundation

public enum SkillText {
    public static func forModel(_ skill: String) -> String {
        var text = skill
        text = cut(text, from: "### render.py", to: ["\n---\n", "\n## "])
        text = cut(text, from: "## 8. Contact sheets", to: ["\n## 9."])
        text = cut(text, from: "## 9. Final message", to: [])
        text = text.replacingOccurrences(of: "rendered frame by frame with Playwright + ffmpeg", with: "rendered frame by frame by Adverb")
        return text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// `text` without the section from `heading` to the first of `ends` (kept), or to the end.
    static func cut(_ text: String, from heading: String, to ends: [String]) -> String {
        guard let start = text.range(of: heading) else { return text }
        let rest = text[start.upperBound...]
        let end = ends.compactMap { rest.range(of: $0)?.lowerBound }.min() ?? text.endIndex
        return String(text[..<start.lowerBound]) + String(text[end...])
    }
}
