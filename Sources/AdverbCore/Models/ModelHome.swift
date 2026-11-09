//
//  ModelHome.swift
//  AdverbCore
//
//  WHAT: Where models live on this Mac: the Rao stack's shared home (AII_HOME, else ~/.rao) under
//        models/huggingface, snapshots at snapshots/models/<org>/<name> — the layout Frigate's
//        HubDownloader, Craft, AII and Sewn read and write, so a model fetched by one is there for
//        the others. Voice packs sit in the same layout.
//  PIN:  Never ~/.cache or ~/Documents. Removing a model removes it for the whole stack: Settings
//        says so before it does.
//

import Foundation

public enum ModelHome {
    public static func huggingFace(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        AdverbHome.root(environment: environment).appendingPathComponent("models/huggingface", isDirectory: true)
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
}
