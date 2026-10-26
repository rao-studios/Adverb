//
//  AtomicFile.swift
//  AdverbCore
//
//  WHAT: Writing and listing files the way the T9 needs: atomic writes, and listings that skip
//        what exFAT and Finder leave behind.
//  PIN:  exFAT stores extended attributes as `._name` sidecar files beside every file macOS
//        touches; they are never Adverb's and are skipped everywhere (listings, the context
//        digest, project discovery). No hard links (exFAT has none): replace is write + rename.
//

import Foundation

public enum AtomicFile {

    /// Writes `data` beside `url` and renames it over: readers see the old file or the new one.
    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public static func write(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }

    /// Copies `source` over `destination`, replacing it: a finished render made in a temporary
    /// folder lands on the drive in one sequential copy.
    public static func replace(_ destination: URL, with source: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staged = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).adverb-\(UUID().uuidString.prefix(8))")
        try? fm.removeItem(at: staged)
        try fm.copyItem(at: source, to: staged)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: destination)
        }
    }

    /// True for exFAT/AppleDouble sidecars (`._name`) and Finder's `.DS_Store`.
    public static func isSidecar(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix("._") || name == ".DS_Store"
    }

    /// The visible entries of `directory`: no hidden files, no sidecars. Sorted by name.
    public static func contents(of directory: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return entries.filter { !isSidecar($0) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Bytes under `url`, recursively (sidecars included: they are on the disk too).
    public static func size(of url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }
}
