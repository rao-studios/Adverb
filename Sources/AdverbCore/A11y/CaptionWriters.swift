//
//  CaptionWriters.swift
//  AdverbCore
//
//  WHAT: Cues to WebVTT (the accessibility track and web players), SRT (the platforms that take
//        an uploaded caption file), and a Markdown transcript.
//

import Foundation

public enum WebVTTWriter {
    public enum Kind: String { case captions, descriptions }

    public static func write(_ cues: [Cue], kind: Kind = .captions, language: String = "en", title: String? = nil) -> String {
        var out = "WEBVTT"
        if let title { out += " - \(escape(title))" }
        out += "\nKind: \(kind.rawValue)\nLanguage: \(language)\n"
        for (i, cue) in cues.enumerated() {
            out += "\n\(i + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(escape(cue.text))\n"
        }
        return out
    }

    /// hh:mm:ss.mmm
    public static func timestamp(_ t: Double) -> String {
        let ms = Int((max(0, t) * 1000).rounded())
        return String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "-->", with: "→")
    }
}

public enum SRTWriter {
    public static func write(_ cues: [Cue]) -> String {
        cues.enumerated().map { i, cue in
            "\(i + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    /// hh:mm:ss,mmm
    public static func timestamp(_ t: Double) -> String {
        WebVTTWriter.timestamp(t).replacingOccurrences(of: ".", with: ",")
    }
}

public enum TranscriptWriter {
    /// The words on screen, the descriptions of what is shown, the music, and (when the asset is
    /// narrated) what the voice says, in time order.
    public static func write(title: String, captions: [Cue], descriptions: [Cue], altText: String, music: String?, said: [Cue] = []) -> String {
        var out = "# \(title)\n\n"
        if !altText.isEmpty { out += "**Alt text.** \(altText)\n\n" }
        if let music { out += "**Music.** \(music)\n\n" }
        let all = (captions.filter { $0.kind != .music }.map { ($0, "Text") } + said.map { ($0, "Said") } + descriptions.map { ($0, "Shown") })
            .sorted { $0.0.start < $1.0.start }
        for (cue, label) in all {
            let text = cue.text.replacingOccurrences(of: "\n", with: " / ")
            out += "- `\(String(format: "%05.2f", cue.start))` \(label): \(text)\n"
        }
        return out
    }
}

public enum WebVTTReader {
    /// The cues of a WebVTT (or SRT) file: times and text, the header and cue numbers skipped.
    public static func parse(_ text: String) -> [Cue] {
        var cues: [Cue] = []
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let i = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[i].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let a = seconds(parts[0]), let b = seconds(parts[1].components(separatedBy: " ").first ?? "") else { continue }
            let body = lines[(i + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
            if !body.isEmpty { cues.append(Cue(start: a, end: b, text: body)) }
        }
        return cues
    }

    static func seconds(_ s: String) -> Double? {
        let parts = s.replacingOccurrences(of: ",", with: ".").split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count) else { return nil }
        let nums = parts.compactMap(Double.init)
        guard nums.count == parts.count else { return nil }
        return nums.count == 3 ? nums[0] * 3600 + nums[1] * 60 + nums[2] : nums[0] * 60 + nums[1]
    }
}
