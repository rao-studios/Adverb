//
//  Workspace.swift
//  AdverbCore
//
//  WHAT: The Adverb folder inside the working directory the person chose, and its index.
//        `<workdir>/Adverb/adverb.json` orders the projects; each project is a folder with a
//        project.json (discovered by scanning, so a folder copied in by hand still appears).
//

import Foundation

public struct WorkspaceIndex: Codable, Sendable, Equatable {
    public var version: Int = 1
    public var createdAt: Date
    public var createdBy: String = "adverb"
    public var projectOrder: [String]
    public var lastOpenedSlug: String?

    public init(createdAt: Date = Date(), projectOrder: [String] = [], lastOpenedSlug: String? = nil) {
        self.createdAt = createdAt; self.projectOrder = projectOrder; self.lastOpenedSlug = lastOpenedSlug
    }
}

public struct Workspace: Sendable, Equatable {
    public let workdir: URL

    public init(workdir: URL) { self.workdir = workdir.standardizedFileURL }

    public var root: URL { workdir.appendingPathComponent("Adverb", isDirectory: true) }
    public var indexFile: URL { root.appendingPathComponent("adverb.json") }
    public func projectFolder(_ slug: String) -> URL { root.appendingPathComponent(slug, isDirectory: true) }
    public func projectFile(_ slug: String) -> URL { projectFolder(slug).appendingPathComponent("project.json") }

    public var gate: VolumeGate.Status { VolumeGate.status(workdir) }

    /// Makes `<workdir>/Adverb` and its index when they are not there. Refuses when the drive is gone.
    public func prepare() throws {
        guard VolumeGate.isUsable(gate) else { throw WorkspaceError.unavailable(gate) }
        if !AtomicFile.isDirectory(root) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: indexFile.path) {
            try JSONCoding.write(WorkspaceIndex(), to: indexFile)
        }
    }

    public func readIndex() -> WorkspaceIndex {
        (try? JSONCoding.read(WorkspaceIndex.self, from: indexFile)) ?? WorkspaceIndex()
    }

    public func writeIndex(_ index: WorkspaceIndex) throws {
        try JSONCoding.write(index, to: indexFile)
    }
}

public enum WorkspaceError: Error, Equatable, CustomStringConvertible {
    case unavailable(VolumeGate.Status)
    case noWorkdir

    public var description: String {
        switch self {
        case .unavailable(.notMounted(let volume)): "\(volume) is not mounted. Plug it in, then try again."
        case .unavailable(.missing): "The working directory is gone. Choose it again in Settings."
        case .unavailable: "The working directory is not available."
        case .noWorkdir: "Choose a working directory first."
        }
    }
}
