//
//  ModelHome.swift
//  AdverbCore
//
//  WHAT: Where models live on this Mac: the folder Settings › Models names, ~/.rao/models unless the
//        person chose another (the Rao stack's shared home: AII_HOME, else ~/.rao). Downloads land in
//        huggingface/snapshots/models/<org>/<name> inside it — the layout Frigate's HubDownloader,
//        Craft, AII and Sewn read and write. Voice packs sit in the same layout.
//  PIN:  The folder is SEARCHED (ModelSearch), and ~/.rao/models with it when another is chosen: a
//        model any Rao app fetched is used where it sits, at any path, and under the name of the
//        repository it was mirrored from when the bytes are the same. Nothing is fetched twice.
//  PIN:  Never ~/.cache or ~/Documents. Removing a model removes it for the whole stack: Settings
//        says so before it does.
//

import Foundation

public enum ModelHome {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var chosen: URL?

    /// The folder models are kept in and looked for: the one chosen in Settings, else ~/.rao/models.
    public static func root(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        lock.withLock { chosen } ?? defaultRoot(environment: environment)
    }

    /// The Rao stack's own: ~/.rao/models (AII_HOME/models when set).
    public static func defaultRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        AdverbHome.root(environment: environment).appendingPathComponent("models", isDirectory: true)
    }

    /// The folder for this process from now on (nil: the default). The app calls it at launch and
    /// whenever the setting changes; the probe once, from the same settings file.
    public static func use(_ folder: URL?) {
        let folder = folder?.standardizedFileURL
        lock.withLock { chosen = folder }
    }

    /// Where a search looks: the chosen folder, then the stack's when it is another.
    public static func searchRoots(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        let roots = [root(environment: environment), defaultRoot(environment: environment)]
        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    public static func huggingFace(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        root(environment: environment).appendingPathComponent("huggingface", isDirectory: true)
    }

    public static func snapshots(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        huggingFace(environment: environment).appendingPathComponent("snapshots", isDirectory: true)
    }

    /// `snapshots/models/<org>/<name>`: where a repository is downloaded to.
    public static func folder(_ repo: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        snapshots(environment: environment).appendingPathComponent("models/\(repo)", isDirectory: true)
    }

    /// The commit a snapshot was fetched at: the first line of the metadata the Hub client writes
    /// beside config.json (or beside `marker`, for a repository without one).
    public static func commit(of folder: URL, marker: String = "config.json") -> String? {
        let metadata = folder.appendingPathComponent(".cache/huggingface/download/\(marker).metadata")
        guard let text = try? String(contentsOf: metadata, encoding: .utf8),
              let first = text.split(whereSeparator: \.isNewline).first else { return nil }
        let commit = first.trimmingCharacters(in: .whitespaces)
        return commit.isEmpty ? nil : commit
    }

    /// A path as a person reads it: "~/.rao/models" for one under the home folder.
    public static func display(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// A typed or chosen path as a folder URL ("~" expanded).
    public static func url(_ path: String) -> URL {
        URL(fileURLWithPath: (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath, isDirectory: true)
    }
}
