//
//  Schemas.swift
//  AdverbCore
//
//  WHAT: The shapes the model's answers are held to: the month's plan, a page's notes and
//        accessibility text (the trailer after the page), a contact sheet's review, a re-timing's
//        cues (after the re-timed page), a narration (written, translated or shortened).
//  PIN:  Objects keep the order their keys are given in (`required` lists them so): the skeleton a
//        model is shown follows it, and a model writes the keys as shown. Counts and lengths are
//        not in the schema; they are checked after (PlanValidator, PageVerifier, NarrationCaptions).
//

import Foundation

public enum Schemas {
    static func object(_ properties: KeyValuePairs<String, JSONValue>) -> JSONValue {
        ["type": "object", "additionalProperties": false,
         "required": .array(properties.map { .string($0.key) }),
         "properties": .object(Dictionary(properties.map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a }))]
    }

    static func array(_ items: JSONValue) -> JSONValue { ["type": "array", "items": items] }
    static let string: JSONValue = ["type": "string"]
    static let number: JSONValue = ["type": "number"]
    static let integer: JSONValue = ["type": "integer"]
    static let boolean: JSONValue = ["type": "boolean"]
    static var platform: JSONValue { ["type": "string", "enum": .array(Platform.allCases.map { .string($0.rawValue) })] }

    public static var plan: JSONValue {
        object([
            "summary": string,
            "arc": array(string),
            "sources": array(string),
            "cautions": array(string),
            "days": array(object([
                "index": integer,
                "date": ["type": "string", "format": "date"],
                "post_time_local": string,
                "time_reason": string,
                "platform": platform,
                "cross_post": array(platform),
                "topic_slug": string,
                "title": string,
                "duration": ["type": "integer", "enum": [15, 30]],
                "kicker": string,
                "headline": string,
                "hook": string,
                "scenes": array(object(["at": number, "until": number, "recipe": string, "what": string])),
                "recipes": array(string),
                "caption": string,
                "hashtags": array(string),
                "cta": string,
            ])),
        ])
    }

    /// What follows a page: its notes and accessibility text.
    public static var pageTrailer: JSONValue {
        object([
            "notes": object(["summary": string, "illustrative": array(string), "softened": array(string), "sources": array(string)]),
            "a11y": object([
                "alt_text": string,
                "descriptions": array(object(["at": number, "until": number, "text": string])),
            ]),
        ])
    }

    /// A review of a contact sheet: whether it is right, and each thing to change. The eyes never
    /// write the page; the writer changes it from these.
    public static var review: JSONValue {
        object(["ok": boolean, "issues": array(string)])
    }

    /// What follows a re-timed page: what was put on the grid.
    public static var retimeTrailer: JSONValue {
        object(["cues": array(object(["t": number, "kind": string]))])
    }

    /// A voice-over: timed lines in page time. The same shape for a translation.
    public static var narration: JSONValue {
        object(["lines": array(object(["at": number, "until": number, "text": string]))])
    }

    // MARK: - Formats

    public static var planFormat: AnswerFormat { .json(plan) }
    public static var pageFormat: AnswerFormat { .document(trailer: pageTrailer, optionalPage: false) }
    public static var reviewFormat: AnswerFormat { .json(review) }
    public static var retimeFormat: AnswerFormat { .document(trailer: retimeTrailer, optionalPage: false) }
    public static var narrationFormat: AnswerFormat { .json(narration) }
}
