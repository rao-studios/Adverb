//
//  ContextDigest.swift
//  AdverbCore
//
//  WHAT: What Claude reads about a project: its README, CLAUDE.md/AGENTS.md, skills, docs, the
//        text of its site pages, its manifest. Read from the context folder (never written), in a
//        fixed order, capped per file and in total, opened by an inventory of everything found so
//        the reader knows what was cut.
//  PIN:  Deterministic: the same folder gives the same bytes, so the digest can sit behind a cache
//        breakpoint and thirty builds read it from cache. It is frozen per campaign
//        (context-digest.md) for the same reason.
//

import CryptoKit
import Foundation

public struct ContextDigest: Sendable, Equatable {
    public struct File: Sendable, Equatable {
        public var path: String
        public var bytes: Int
        public var included: Int
    }

    public var root: String
    public var files: [File]
    public var text: String
    public var tokenEstimate: Int
    public var sha256: String
}

public enum ContextDigestBuilder {
    /// Patterns in priority order. `**` is any depth.
    public static let include = ["README.md", "CLAUDE.md", "AGENTS.md", "SKILL.md", "*/SKILL.md",
                                 "Docs/**/README.md", "docs/**/README.md", "Docs/**/*.md", "docs/**/*.md",
                                 "Docs/site/*.html", "docs/site/*.html", "site/*.html", "README_Assets/*.md",
                                 "Sources/*/README.md", "Package.swift", "package.json"]
    public static let skipDirectories: Set<String> = [".build", "build", ".git", "node_modules", "models", "datasets", "weights",
                                                      ".swiftpm", "dist", "DerivedData", "Pods", "pkg", ".venv", "venv", "__pycache__"]

    public static func build(root: URL, budgetTokens: Int = 60_000, readmeTokens: Int = 16_000, fileTokens: Int = 6_000) -> ContextDigest {
        let candidates = collect(root: root)
        var picked: [(String, URL)] = []
        var seen = Set<String>()
        for pattern in include {
            for (rel, url) in candidates where !seen.contains(rel) && matches(rel, pattern) {
                picked.append((rel, url)); seen.insert(rel)
            }
        }
        var files: [ContextDigest.File] = []
        var bodies: [String] = []
        var used = 0
        for (rel, url) in picked {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var text = rel.hasSuffix(".html") ? htmlText(raw) : raw
            let cap = min(rel == "README.md" ? readmeTokens : fileTokens, max(0, budgetTokens - used))
            let capChars = Int(Double(cap) * 3.5)
            var included = text.count
            if text.count > capChars {
                let cut = text.count - capChars
                text = String(text.prefix(capChars)) + "\n[… \(cut) more characters]"
                included = capChars
            }
            files.append(.init(path: rel, bytes: raw.utf8.count, included: included))
            if cap > 0, !text.isEmpty {
                bodies.append("<file path=\"\(rel)\">\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))\n</file>")
                used += Int(Double(text.count) / 3.5)
            }
        }
        let inventory = files.map { "- \($0.path) (\($0.bytes) bytes\($0.included < $0.bytes ? ", \($0.included) characters read" : ""))" }
        let header = "# Project context: \(root.lastPathComponent)\n\nRead from the project's own folder. Files found, in the order given:\n\n"
            + (inventory.isEmpty ? "- (no README or docs were found)" : inventory.joined(separator: "\n")) + "\n\n"
        let text = header + bodies.joined(separator: "\n\n") + "\n"
        return ContextDigest(root: root.path, files: files, text: text, tokenEstimate: Int(Double(text.count) / 3.5), sha256: sha(text))
    }

    public static func sha(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Every file under `root` (relative path, URL), skipping build products, VCS, sidecars and
    /// anything over 2 MB. Sorted.
    static func collect(root: URL, maxDepth: Int = 5) -> [(String, URL)] {
        var out: [(String, URL)] = []
        func walk(_ dir: URL, _ prefix: String, _ depth: Int) {
            guard depth <= maxDepth else { return }
            for entry in AtomicFile.contents(of: dir) {
                let name = entry.lastPathComponent
                let rel = prefix.isEmpty ? name : "\(prefix)/\(name)"
                if AtomicFile.isDirectory(entry) {
                    if !skipDirectories.contains(name) { walk(entry, rel, depth + 1) }
                } else {
                    let size = (try? entry.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    if size > 0, size <= 2_000_000 { out.append((rel, entry)) }
                }
            }
        }
        walk(root, "", 0)
        return out.sorted { $0.0 < $1.0 }
    }

    /// `pattern` against a relative path: `*` within a segment, `**` across segments.
    static func matches(_ path: String, _ pattern: String) -> Bool {
        var regex = "^"
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            if c == "*" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex, pattern[next] == "*" {
                    regex += ".*"; i = pattern.index(after: next)
                    if i < pattern.endIndex, pattern[i] == "/" { regex += "/?"; i = pattern.index(after: i) }
                    continue
                }
                regex += "[^/]*"
            } else if ".+?()[]{}^$|\\".contains(c) {
                regex += "\\\(c)"
            } else {
                regex.append(c)
            }
            i = pattern.index(after: i)
        }
        regex += "$"
        return path.range(of: regex, options: .regularExpression) != nil
    }

    /// The readable text of an HTML page: title, description, then the body without tags.
    static func htmlText(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "svg", "noscript"] {
            s = s.replacingOccurrences(of: "(?s)<\(tag)[^>]*>.*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        let title = html.range(of: "<title>(.*?)</title>", options: [.regularExpression, .caseInsensitive])
            .map { String(html[$0]).replacingOccurrences(of: "</?title>", with: "", options: .regularExpression) }
        s = s.replacingOccurrences(of: "<br\\s*/?>|</p>|</h[1-6]>|</li>|</div>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        let lines = s.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (title.map { "Title: \($0)\n" } ?? "") + lines.joined(separator: "\n")
    }
}
