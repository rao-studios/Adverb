//
//  SongLibrary.swift
//  AdverbRender
//
//  WHAT: The songs the person can cut an asset to: every audio file in their music folder (and
//        any they added one by one), with title, artist and length from the file's own metadata.
//  PIN:  Read only. Songs are never copied into a project; the music record keeps the path.
//        ~/Music/Music (the Music app's library) is privacy-protected: a folder there needs the
//        person's permission, which the open panel grants when they choose it.
//

@preconcurrency import AVFoundation
import Foundation
import UniformTypeIdentifiers

public struct Song: Sendable, Equatable, Identifiable, Hashable, Codable {
    public var path: String
    public var title: String
    public var artist: String?
    public var duration: Double

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
    public var credit: String { artist.map { "\(title) — \($0)" } ?? title }

    public init(path: String, title: String, artist: String?, duration: Double) {
        self.path = path; self.title = title; self.artist = artist; self.duration = duration
    }
}

public enum SongLibrary {
    /// Audio files under `folder` (two levels deep), sorted by title.
    public static func scan(_ folder: URL, depth: Int = 2) async -> [Song] {
        var urls: [URL] = []
        func walk(_ dir: URL, _ level: Int) {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentTypeKey, .isDirectoryKey],
                                                                            options: [.skipsHiddenFiles]) else { return }
            for url in entries where !url.lastPathComponent.hasPrefix("._") {
                let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
                if values?.isDirectory == true {
                    if level < depth { walk(url, level + 1) }
                } else if values?.contentType?.conforms(to: .audio) == true {
                    urls.append(url)
                }
            }
        }
        walk(folder, 0)
        var songs: [Song] = []
        for url in urls { if let song = await song(url) { songs.append(song) } }
        return songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public static func song(_ url: URL) async -> Song? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return nil }
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        func value(_ key: AVMetadataKey) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: .common).first else { return nil }
            return try? await item.load(.stringValue)
        }
        let title = await value(.commonKeyTitle) ?? url.deletingPathExtension().lastPathComponent
        let artist = await value(.commonKeyArtist)
        return Song(path: url.path, title: title, artist: artist, duration: duration)
    }
}
