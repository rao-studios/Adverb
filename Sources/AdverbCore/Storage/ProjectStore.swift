//
//  ProjectStore.swift
//  AdverbCore
//
//  WHAT: The projects in a workspace: list (by scanning */project.json, in the index's order),
//        create (folder, project.json, kit), update, remove.
//  PIN:  Remove never touches the context folder. With `deleteFolder`, it removes the project's
//        Adverb folder; without, it only forgets the project, and its folder stays, renamed
//        aside so a later project can take the slug (`<slug>.removed-<date>`).
//

import Foundation

public struct ProjectStore: Sendable {
    public let workspace: Workspace

    public init(workspace: Workspace) { self.workspace = workspace }

    public func list() -> [Project] {
        let found = AtomicFile.contents(of: workspace.root)
            .filter { AtomicFile.isDirectory($0) && !$0.lastPathComponent.contains(".removed-") }
            .compactMap { try? JSONCoding.read(Project.self, from: $0.appendingPathComponent("project.json")) }
        let order = workspace.readIndex().projectOrder
        return found.sorted { a, b in
            let ia = order.firstIndex(of: a.slug) ?? Int.max, ib = order.firstIndex(of: b.slug) ?? Int.max
            return ia != ib ? ia < ib : a.createdAt < b.createdAt
        }
    }

    public func create(name: String, contextPath: String, app: AppIdentity, label: ProjectLabel = .gold, tags: [String] = []) throws -> Project {
        try workspace.prepare()
        guard AtomicFile.isDirectory(URL(fileURLWithPath: contextPath)) else { throw ProjectError.contextMissing(contextPath) }
        let taken = Set(AtomicFile.contents(of: workspace.root).map(\.lastPathComponent))
        let slug = Slug.unique(name, taken: taken)
        let folder = workspace.projectFolder(slug)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("campaigns"), withIntermediateDirectories: true)
        let version = try KitInstaller.install(into: folder.appendingPathComponent("kit", isDirectory: true))
        let project = Project(slug: slug, name: name, contextPath: contextPath, app: app, label: label, tags: tags, kitVersion: version)
        try save(project)
        var index = workspace.readIndex()
        index.projectOrder.removeAll { $0 == slug }
        index.projectOrder.append(slug)
        index.lastOpenedSlug = slug
        try workspace.writeIndex(index)
        return project
    }

    public func save(_ project: Project) throws {
        var project = project
        project.updatedAt = Date()
        try JSONCoding.write(project, to: workspace.projectFile(project.slug))
    }

    /// The project's kit, refreshed when the app's is newer.
    @discardableResult
    public func ensureKit(_ project: Project) throws -> Project {
        let version = try KitInstaller.install(into: workspace.projectFolder(project.slug).appendingPathComponent("kit", isDirectory: true))
        guard version != project.kitVersion else { return project }
        var updated = project
        updated.kitVersion = version
        try save(updated)
        return updated
    }

    public func remove(_ project: Project, deleteFolder: Bool) throws {
        let folder = workspace.projectFolder(project.slug)
        // Never the context folder: only ever this project's own folder under <workdir>/Adverb.
        precondition(folder.standardizedFileURL.path.hasPrefix(workspace.root.standardizedFileURL.path + "/"))
        if AtomicFile.isDirectory(folder) {
            if deleteFolder {
                try FileManager.default.removeItem(at: folder)
            } else {
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
                try FileManager.default.moveItem(at: folder, to: workspace.root.appendingPathComponent("\(project.slug).removed-\(stamp)"))
            }
        }
        var index = workspace.readIndex()
        index.projectOrder.removeAll { $0 == project.slug }
        if index.lastOpenedSlug == project.slug { index.lastOpenedSlug = index.projectOrder.first }
        try workspace.writeIndex(index)
    }

    public func size(_ project: Project) -> Int64 { AtomicFile.size(of: workspace.projectFolder(project.slug)) }
}

public enum ProjectError: Error, Equatable, CustomStringConvertible {
    case contextMissing(String)

    public var description: String {
        switch self {
        case .contextMissing(let path): "The context folder is not there: \(path)"
        }
    }
}
