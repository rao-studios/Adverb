//
//  Project.swift
//  AdverbCore
//
//  WHAT: A project in Adverb: a name, a label, and the folder it takes its context from.
//  PIN:  `contextPath` is read and never written. Removing a project from Adverb removes its
//        Adverb folder (when asked) and nothing else.
//

import Foundation

public struct Project: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var version: Int = 1
    public var id: UUID
    /// The folder name under `<workdir>/Adverb/`: lowercase kebab, unique case-insensitively.
    public var slug: String
    public var name: String
    /// The existing folder this project is about (an app's repo, a site): context only.
    public var contextPath: String
    public var app: AppIdentity
    public var label: ProjectLabel
    public var tags: [String]
    public var notes: String
    public var kitVersion: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), slug: String, name: String, contextPath: String, app: AppIdentity,
                label: ProjectLabel = .gold, tags: [String] = [], notes: String = "", kitVersion: String = "",
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.slug = slug; self.name = name; self.contextPath = contextPath; self.app = app
        self.label = label; self.tags = tags; self.notes = notes; self.kitVersion = kitVersion
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public var contextURL: URL { URL(fileURLWithPath: contextPath, isDirectory: true) }
}

/// The colour dot beside a project: the skill's lane colours.
public enum ProjectLabel: String, Codable, Sendable, CaseIterable, Hashable {
    case gold, night, teal, platinum, ink
}
