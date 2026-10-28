//
//  Responses.swift
//  AdverbCore
//
//  WHAT: Claude's structured answers as Swift values (the shapes Schemas describes).
//

import Foundation

public struct PlanResponse: Codable, Sendable, Equatable {
    public struct Scene: Codable, Sendable, Equatable {
        public var at: Double; public var until: Double; public var recipe: String; public var what: String
        public init(at: Double, until: Double, recipe: String, what: String) { self.at = at; self.until = until; self.recipe = recipe; self.what = what }
    }
    public struct Day: Codable, Sendable, Equatable {
        public var index: Int
        public var date: String
        public var post_time_local: String
        public var time_reason: String
        public var platform: String
        public var cross_post: [String]
        public var topic_slug: String
        public var title: String
        public var duration: Int
        public var kicker: String
        public var headline: String
        public var hook: String
        public var scenes: [Scene]
        public var recipes: [String]
        public var caption: String
        public var hashtags: [String]
        public var cta: String

        public init(index: Int, date: String, post_time_local: String, time_reason: String, platform: String, cross_post: [String],
                    topic_slug: String, title: String, duration: Int, kicker: String, headline: String, hook: String, scenes: [Scene],
                    recipes: [String], caption: String, hashtags: [String], cta: String) {
            self.index = index; self.date = date; self.post_time_local = post_time_local; self.time_reason = time_reason
            self.platform = platform; self.cross_post = cross_post; self.topic_slug = topic_slug; self.title = title
            self.duration = duration; self.kicker = kicker; self.headline = headline; self.hook = hook; self.scenes = scenes
            self.recipes = recipes; self.caption = caption; self.hashtags = hashtags; self.cta = cta
        }
    }
    public var summary: String
    public var arc: [String]
    public var sources: [String]
    public var cautions: [String]
    public var days: [Day]

    public init(summary: String, arc: [String], sources: [String], cautions: [String], days: [Day]) {
        self.summary = summary; self.arc = arc; self.sources = sources; self.cautions = cautions; self.days = days
    }
}

public struct PageResponse: Codable, Sendable, Equatable {
    public struct Notes: Codable, Sendable, Equatable { public var summary: String; public var illustrative: [String]; public var softened: [String]; public var sources: [String] }
    public struct Description: Codable, Sendable, Equatable { public var at: Double; public var until: Double; public var text: String }
    public struct A11yText: Codable, Sendable, Equatable { public var alt_text: String; public var descriptions: [Description] }
    public var html: String
    public var notes: Notes
    public var a11y: A11yText

    public init(html: String, notes: Notes, a11y: A11yText) { self.html = html; self.notes = notes; self.a11y = a11y }
}

public struct ReviewResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var issues: [String]
    public var html: String
}

public struct RetimeResponse: Codable, Sendable, Equatable {
    public struct CueMark: Codable, Sendable, Equatable { public var t: Double; public var kind: String }
    public var html: String
    public var cues: [CueMark]
}

public struct NarrationResponse: Codable, Sendable, Equatable {
    public struct Line: Codable, Sendable, Equatable { public var at: Double; public var until: Double; public var text: String
        public init(at: Double, until: Double, text: String) { self.at = at; self.until = until; self.text = text } }
    public var lines: [Line]
    public init(lines: [Line]) { self.lines = lines }
}
