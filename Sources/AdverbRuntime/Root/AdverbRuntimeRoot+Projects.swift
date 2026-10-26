//
//  AdverbRuntimeRoot+Projects.swift
//  AdverbRuntime
//
//  WHAT: Projects: list, create from a context folder, edit, remove (keeping or deleting the
//        project's Adverb folder; never the context folder).
//

import AdverbCore
import Foundation

extension AdverbRuntimeRoot {
    public func reloadProjects() async {
        guard let workspace else { projects.set(.loaded([])); projectCount = 0; return }
        let list = await Task.detached { ProjectStore(workspace: workspace).list() }.value
        projectCount = list.count
        projects.set(.loaded(list))
        for project in list { await reloadCampaigns(project.slug) }
    }

    @discardableResult
    public func createProject(name: String, context: URL, app: AppIdentity, label: ProjectLabel, tags: [String]) async -> Project? {
        guard let workspace else { config.set(.problem("Choose a working directory first.")); return nil }
        do {
            let project = try await Task.detached {
                try ProjectStore(workspace: workspace).create(name: name, contextPath: context.standardizedFileURL.path, app: app, label: label, tags: tags)
            }.value
            projects.set(.saved(project))
            projectCount += 1
            campaigns.set(.loaded(slug: project.slug, []))
            config.set(.gate(.ready))
            config.set(.notice("\(project.name) is in \(workspace.projectFolder(project.slug).path)."))
            update { $0.lastProjectSlug = project.slug }
            return project
        } catch {
            config.set(.problem("\(error)"))
            return nil
        }
    }

    public func saveProject(_ project: Project) async {
        guard let workspace else { return }
        do {
            try await Task.detached { try ProjectStore(workspace: workspace).save(project) }.value
            var saved = project
            saved.updatedAt = Date()
            projects.set(.saved(saved))
        } catch {
            config.set(.problem("\(error)"))
        }
    }

    public func removeProject(_ project: Project, deleteFolder: Bool) async {
        guard let workspace else { return }
        generation.center.$builder.cancel(prefix: "")
        do {
            try await Task.detached { try ProjectStore(workspace: workspace).remove(project, deleteFolder: deleteFolder) }.value
            projects.set(.removed(slug: project.slug))
            projectCount = max(0, projectCount - 1)
            campaigns.set(.forgetProject(project.slug))
            config.set(.notice(deleteFolder ? "\(project.name) and its Adverb folder were removed. \(project.contextPath) was not touched."
                                            : "\(project.name) was removed from Adverb; its folder was kept. \(project.contextPath) was not touched."))
            if projectCount == 0 { config.set(.gate(.noProjects)) }
        } catch {
            config.set(.problem("\(error)"))
        }
    }

    public func projectFolder(_ project: Project) -> URL? { workspace?.projectFolder(project.slug) }

    public func folderSize(_ project: Project) async -> Int64 {
        guard let workspace else { return 0 }
        return await Task.detached { ProjectStore(workspace: workspace).size(project) }.value
    }
}
