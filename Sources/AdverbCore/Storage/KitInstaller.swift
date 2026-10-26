//
//  KitInstaller.swift
//  AdverbCore
//
//  WHAT: Puts the motion kit (kit.css, kit.js, dev.css, dev.js, kit-beat.js, render.py, fonts,
//        the seal and its texture) into a project's folder, so every page there resolves it
//        relatively and a project folder renders on its own, even without Adverb.
//  PIN:  Copied, not linked: exFAT has no hard links, and a symlink into the app bundle breaks the
//        moment the app moves. Re-copied when the bundled KIT-VERSION is newer.
//

import Foundation

public enum KitInstaller {
    public static let files = ["kit.css", "kit.js", "dev.css", "dev.js", "kit-beat.js", "render.py", "render-frames.py", "KIT-VERSION",
                               "fonts/instrument-serif-latin-400-normal.woff2", "fonts/instrument-serif-latin-400-italic.woff2",
                               "fonts/newsreader-latin-400-normal.woff2", "fonts/newsreader-latin-400-italic.woff2",
                               "fonts/jetbrains-mono-latin-400-normal.woff2", "fonts/jetbrains-mono-latin-500-normal.woff2",
                               "assets/rao-hero.png", "assets/rao-tex.jpg"]

    public static var bundledVersion: String {
        KitBundle.text("Kit/KIT-VERSION")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
    }

    public static func installedVersion(in kit: URL) -> String? {
        (try? String(contentsOf: kit.appendingPathComponent("KIT-VERSION"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Copies the kit into `destination` when it is missing, stale or incomplete. Returns the version.
    @discardableResult
    public static func install(into destination: URL, from source: URL? = KitBundle.kit) throws -> String {
        guard let source else { throw KitError.bundleMissing }
        let version = (try? String(contentsOf: source.appendingPathComponent("KIT-VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        let fm = FileManager.default
        let complete = files.allSatisfy { fm.fileExists(atPath: destination.appendingPathComponent($0).path) }
        if complete, installedVersion(in: destination) == version { return version }
        for file in files {
            let from = source.appendingPathComponent(file)
            guard fm.fileExists(atPath: from.path) else { throw KitError.fileMissing(file) }
            try AtomicFile.write(try Data(contentsOf: from), to: destination.appendingPathComponent(file))
        }
        return version
    }
}

public enum KitError: Error, Equatable, CustomStringConvertible {
    case bundleMissing
    case fileMissing(String)

    public var description: String {
        switch self {
        case .bundleMissing: "Adverb's kit resources are missing from the app. Rebuild it with Scripts/make-app.sh."
        case .fileMissing(let file): "The kit is missing \(file)."
        }
    }
}
