//
//  Schemas.swift
//  AdverbCore
//
//  WHAT: The JSON schemas Claude's answers are held to (structured outputs): the month's plan, an
//        asset's page, a stills review, a re-timing, a narration (written or translated).
//  PIN:  Structured outputs want `additionalProperties: false` and every key `required` on every
//        object, and take no length or count limits: those are checked after (PlanValidator).
//

import Foundation

public enum Schemas {
    static func object(_ properties: [String: JSONValue]) -> JSONValue {
        ["type": "object", "additionalProperties": false,
         "required": .array(properties.keys.sorted().map { .string($0) }), "properties": .object(properties)]
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

    public static var page: JSONValue {
        object([
            "html": string,
            "notes": object(["summary": string, "illustrative": array(string), "softened": array(string), "sources": array(string)]),
            "a11y": object([
                "alt_text": string,
                "descriptions": array(object(["at": number, "until": number, "text": string])),
            ]),
        ])
    }

    public static var review: JSONValue {
        object(["ok": boolean, "issues": array(string), "html": string])
    }

    public static var retime: JSONValue {
        object(["html": string, "cues": array(object(["t": number, "kind": string]))])
    }

    /// A voice-over: timed lines in page time. The same shape for a translation.
    public static var narration: JSONValue {
        object(["lines": array(object(["at": number, "until": number, "text": string]))])
    }
}
