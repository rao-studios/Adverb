//
//  Responses.swift
//  AdverbCore
//
//  WHAT: The model's structured answers as Swift values (the shapes Schemas describes).
//  PIN:  Tolerant: a key a model left out reads as empty (an empty list, an empty string, zero), a
//        number written as a string reads as the number, one string where a list was asked reads
//        as a list of one. The validators after decoding say what an empty value breaks, and the
//        fix round asks for it. Only the plan's days and a narration's lines are required.
//

import Foundation

public struct PlanResponse: Codable, Sendable, Equatable {
    public struct Scene: Codable, Sendable, Equatable {
        public var at: Double; public var until: Double; public var recipe: String; public var what: String
        public init(at: Double, until: Double, recipe: String, what: String) { self.at = at; self.until = until; self.recipe = recipe; self.what = what }

        enum CodingKeys: String, CodingKey { case at, until, recipe, what }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(at: c.number(.at), until: c.number(.until), recipe: c.lenient(String.self, .recipe, ""), what: c.lenient(String.self, .what, ""))
        }
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

        enum CodingKeys: String, CodingKey {
            case index, date, post_time_local, time_reason, platform, cross_post, topic_slug, title, duration, kicker, headline, hook,
                 scenes, recipes, caption, hashtags, cta
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(index: c.integer(.index), date: c.lenient(String.self, .date, ""), post_time_local: c.lenient(String.self, .post_time_local, ""),
                      time_reason: c.lenient(String.self, .time_reason, ""), platform: c.lenient(String.self, .platform, ""),
                      cross_post: c.strings(.cross_post), topic_slug: c.lenient(String.self, .topic_slug, ""), title: c.lenient(String.self, .title, ""),
                      duration: c.integer(.duration), kicker: c.lenient(String.self, .kicker, ""), headline: c.lenient(String.self, .headline, ""),
                      hook: c.lenient(String.self, .hook, ""), scenes: c.lenient([Scene].self, .scenes, []), recipes: c.strings(.recipes),
                      caption: c.lenient(String.self, .caption, ""), hashtags: c.strings(.hashtags), cta: c.lenient(String.self, .cta, ""))
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

    enum CodingKeys: String, CodingKey { case summary, arc, sources, cautions, days }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(summary: c.lenient(String.self, .summary, ""), arc: c.strings(.arc), sources: c.strings(.sources),
                  cautions: c.strings(.cautions), days: try c.decode([Day].self, forKey: .days))
    }
}

public struct PageResponse: Codable, Sendable, Equatable {
    public struct Notes: Codable, Sendable, Equatable {
        public var summary: String; public var illustrative: [String]; public var softened: [String]; public var sources: [String]
        public init(summary: String = "", illustrative: [String] = [], softened: [String] = [], sources: [String] = []) {
            self.summary = summary; self.illustrative = illustrative; self.softened = softened; self.sources = sources
        }

        enum CodingKeys: String, CodingKey { case summary, illustrative, softened, sources }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(summary: c.lenient(String.self, .summary, ""), illustrative: c.strings(.illustrative), softened: c.strings(.softened),
                      sources: c.strings(.sources))
        }
    }

    public struct Description: Codable, Sendable, Equatable {
        public var at: Double; public var until: Double; public var text: String
        public init(at: Double, until: Double, text: String) { self.at = at; self.until = until; self.text = text }

        enum CodingKeys: String, CodingKey { case at, until, text }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(at: c.number(.at), until: c.number(.until), text: c.lenient(String.self, .text, ""))
        }
    }

    public struct A11yText: Codable, Sendable, Equatable {
        public var alt_text: String; public var descriptions: [Description]
        public init(alt_text: String = "", descriptions: [Description] = []) { self.alt_text = alt_text; self.descriptions = descriptions }

        enum CodingKeys: String, CodingKey { case alt_text, descriptions }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(alt_text: c.lenient(String.self, .alt_text, ""), descriptions: c.lenient([Description].self, .descriptions, []))
        }
    }

    public var html: String
    public var notes: Notes
    public var a11y: A11yText

    public init(html: String, notes: Notes = Notes(), a11y: A11yText = A11yText()) { self.html = html; self.notes = notes; self.a11y = a11y }

    enum CodingKeys: String, CodingKey { case html, notes, a11y }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(html: c.lenient(String.self, .html, ""), notes: c.lenient(Notes.self, .notes, Notes()), a11y: c.lenient(A11yText.self, .a11y, A11yText()))
    }
}

public struct ReviewResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var issues: [String]
    /// The corrected page; empty when the stills need no change.
    public var html: String

    public init(ok: Bool, issues: [String], html: String) { self.ok = ok; self.issues = issues; self.html = html }

    enum CodingKeys: String, CodingKey { case ok, issues, html }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let issues = c.strings(.issues)
        self.init(ok: c.lenient(Bool.self, .ok, issues.isEmpty), issues: issues, html: c.lenient(String.self, .html, ""))
    }
}

public struct RetimeResponse: Codable, Sendable, Equatable {
    public struct CueMark: Codable, Sendable, Equatable {
        public var t: Double; public var kind: String
        public init(t: Double, kind: String) { self.t = t; self.kind = kind }

        enum CodingKeys: String, CodingKey { case t, kind }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(t: c.number(.t), kind: c.lenient(String.self, .kind, ""))
        }
    }
    public var html: String
    public var cues: [CueMark]

    public init(html: String, cues: [CueMark]) { self.html = html; self.cues = cues }

    enum CodingKeys: String, CodingKey { case html, cues }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(html: c.lenient(String.self, .html, ""), cues: c.lenient([CueMark].self, .cues, []))
    }
}

public struct NarrationResponse: Codable, Sendable, Equatable {
    public struct Line: Codable, Sendable, Equatable {
        public var at: Double; public var until: Double; public var text: String
        public init(at: Double, until: Double, text: String) { self.at = at; self.until = until; self.text = text }

        enum CodingKeys: String, CodingKey { case at, until, text }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(at: c.number(.at), until: c.number(.until), text: c.lenient(String.self, .text, ""))
        }
    }
    public var lines: [Line]
    public init(lines: [Line]) { self.lines = lines }

    enum CodingKeys: String, CodingKey { case lines }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(lines: try c.decode([Line].self, forKey: .lines))
    }
}

// MARK: - Tolerant decoding

extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }

    /// A number, also when written as a string ("2.5").
    func number(_ key: Key) -> Double {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key), let d = Double(s.trimmingCharacters(in: .whitespaces)) { return d }
        return 0
    }

    func integer(_ key: Key) -> Int {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        return Int(number(key).rounded())
    }

    /// A list of strings, also when written as one string.
    func strings(_ key: Key) -> [String] {
        if let list = try? decodeIfPresent([String].self, forKey: key) { return list }
        if let one = try? decodeIfPresent(String.self, forKey: key), !one.isEmpty { return [one] }
        return []
    }
}
