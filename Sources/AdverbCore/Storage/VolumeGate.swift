//
//  VolumeGate.swift
//  AdverbCore
//
//  WHAT: Whether the working directory's drive is here. Adverb works on an external drive (the
//        T9); unplugged, it stops and says so instead of writing anywhere else.
//  PIN:  Veil's rule (VeilSecrets.volumeName/volumeMounted): /Volumes belongs to root, so a
//        missing /Volumes/<name> means the disk is unplugged, and nothing may be created under it
//        meanwhile (it would land on the boot disk, or fail).
//

import Foundation

public enum VolumeGate {
    public enum Status: Sendable, Equatable {
        case mounted(volume: String)
        case notMounted(volume: String)
        case bootVolume
        case missing
    }

    /// "T9" for /Volumes/T9/…, nil for the boot volume.
    public static func volumeName(_ url: URL) -> String? {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count >= 3, parts[0] == "/", parts[1] == "Volumes" else { return nil }
        return parts[2]
    }

    public static func status(_ workdir: URL, fileManager: FileManager = .default) -> Status {
        if let name = volumeName(workdir) {
            var isDirectory: ObjCBool = false
            let mounted = fileManager.fileExists(atPath: "/Volumes/\(name)", isDirectory: &isDirectory) && isDirectory.boolValue
            guard mounted else { return .notMounted(volume: name) }
            return AtomicFile.isDirectory(workdir) ? .mounted(volume: name) : .missing
        }
        return AtomicFile.isDirectory(workdir) ? .bootVolume : .missing
    }

    public static func isUsable(_ status: Status) -> Bool {
        switch status {
        case .mounted, .bootVolume: true
        case .notMounted, .missing: false
        }
    }
}
