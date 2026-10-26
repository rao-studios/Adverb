//
//  PageVerifier.swift
//  AdverbCore
//
//  WHAT: A page Claude wrote, made to resolve and checked before anything renders it: the kit's
//        files pointed at the project's kit folder, and the page contract (rao-motion-assets §6
//        and Adverb's addendum) checked statically. What is wrong goes back to Claude once.
//

import Foundation

public enum PageVerifier {
    static let kitFiles = ["kit.css", "kit.js", "dev.css", "dev.js", "kit-beat.js"]

    /// `href="kit.css"` → `href="../../../../kit/kit.css"`, from the page's folder to the kit's.
    public static func rewriteKitPaths(_ html: String, pageFolder: URL, kitFolder: URL) -> String {
        let prefix = relativePath(from: pageFolder, to: kitFolder)
        var out = html
        for file in kitFiles {
            for attr in ["href", "src"] {
                for quote in ["\"", "'"] {
                    out = out.replacingOccurrences(of: "\(attr)=\(quote)\(file)\(quote)", with: "\(attr)=\(quote)\(prefix)\(file)\(quote)")
                    out = out.replacingOccurrences(of: "\(attr)=\(quote)./\(file)\(quote)", with: "\(attr)=\(quote)\(prefix)\(file)\(quote)")
                }
            }
        }
        return out
    }

    /// The relative path from one folder to another, ending in "/". kit.css resolves the kit's
    /// fonts and images relative to itself, so pointing the page at kit/ is enough; pages never
    /// reference fonts/ or assets/ directly (the addendum says so).
    public static func relativePath(from: URL, to: URL) -> String {
        let a = from.standardizedFileURL.pathComponents, b = to.standardizedFileURL.pathComponents
        var i = 0
        while i < min(a.count, b.count), a[i] == b[i] { i += 1 }
        let ups = Array(repeating: "..", count: a.count - i)
        let downs = Array(b[i...])
        let joined = (ups + downs).joined(separator: "/")
        return joined.isEmpty ? "" : joined + "/"
    }

    /// The page contract, statically.
    public static func problems(_ html: String, duration: Int) -> [String] {
        var out: [String] = []
        let lower = html.lowercased()
        if !lower.contains("<!doctype html") { out.append("Start with <!doctype html>.") }
        if html.range(of: #"window\.DUR\s*=\s*\#(duration)\b"#, options: .regularExpression) == nil {
            out.append("Set window.DUR=\(duration).")
        }
        if !html.contains("ready({") { out.append("Boot the page with ready({...}) from kit.js.") }
        if !html.contains("kit.js") || !html.contains("kit.css") { out.append("Link kit.css and load kit.js exactly as the page template does.") }
        if html.range(of: #"window\.SCENES\s*=\s*\["#, options: .regularExpression) == nil {
            out.append("Set window.SCENES=[…] to the start time of each scene (0 first, the end card last).")
        }
        for banned in ["Math.random", "setTimeout", "setInterval", "Date.now", "performance.now", "requestAnimationFrame"] where html.contains(banned) {
            out.append("Remove \(banned): every frame must be a pure function of t.")
        }
        for banned in ["backdrop-filter", "<video", "<canvas", "webgl"] where lower.contains(banned) {
            out.append("Remove \(banned): the renderer paints in software and drops it.")
        }
        if !html.contains("body.P") || !html.contains("body.L") {
            out.append("Lay out both orientations with body.P and body.L rules.")
        }
        if html.range(of: #"(?i)\b0?\d\s*/\s*\d+\b.*(asset|reel|part)"#, options: .regularExpression) != nil {
            out.append("Never number assets on screen.")
        }
        return out
    }

    /// The scene starts a page declares (`window.SCENES=[…]`), for the warp and the checks.
    public static func scenes(_ html: String) -> [Double] {
        guard let r = html.range(of: #"window\.SCENES\s*=\s*\[([^\]]*)\]"#, options: .regularExpression) else { return [] }
        let inner = html[r].drop { $0 != "[" }.dropFirst().prefix { $0 != "]" }
        return inner.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }
}
