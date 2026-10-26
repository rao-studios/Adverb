//
//  ProjectOps.swift
//  AdverbRuntime
//

import Foundation

public enum ProjectOps {
    public static func apply(_ kind: ProjectService.Set.Meta.Kind, to state: inout ProjectService.Center.State) {
        switch kind {
        case .loaded(let projects):
            state.projects = projects
            state.loaded = true
        case .saved(let project):
            if let i = state.projects.firstIndex(where: { $0.slug == project.slug }) { state.projects[i] = project }
            else { state.projects.append(project) }
        case .removed(let slug):
            state.projects.removeAll { $0.slug == slug }
        }
    }
}
