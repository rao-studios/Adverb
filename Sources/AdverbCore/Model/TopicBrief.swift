//
//  TopicBrief.swift
//  AdverbCore
//
//  WHAT: What one asset is about, as the planner wrote it: the title, the headline, the length,
//        and the scenes in order with the recipe each uses (rao-motion-assets §7).
//

import Foundation

public struct SceneBeat: Codable, Sendable, Equatable, Hashable {
    public var at: Double
    public var until: Double
    public var recipe: String
    public var what: String

    public init(at: Double, until: Double, recipe: String, what: String) {
        self.at = at; self.until = until; self.recipe = recipe; self.what = what
    }
}

public struct TopicBrief: Codable, Sendable, Equatable, Hashable {
    public var slug: String
    public var title: String
    /// 15 or 30 seconds.
    public var duration: Int
    public var kicker: String
    public var headline: String
    public var scenes: [SceneBeat]
    public var recipes: [String]

    public init(slug: String, title: String, duration: Int, kicker: String, headline: String, scenes: [SceneBeat], recipes: [String]) {
        self.slug = slug; self.title = title; self.duration = duration; self.kicker = kicker
        self.headline = headline; self.scenes = scenes; self.recipes = recipes
    }
}
