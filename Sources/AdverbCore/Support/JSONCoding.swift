//
//  JSONCoding.swift
//  AdverbCore
//
//  WHAT: The one JSON encoder and decoder Adverb writes its files with (project.json,
//        campaign.json, settings.json, run logs).
//  PIN:  Sorted keys and ISO-8601 dates, so the same value always encodes to the same bytes
//        (RaoLM's JSONCoding). Writes are atomic: a temporary file renamed over the old one,
//        which exFAT (the T9) supports; a half-written campaign.json never exists.
//

import Foundation

public enum JSONCoding {

    /// Pretty, sorted, stable. For files people read.
    public static func prettyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }

    /// Compact, sorted, stable. For JSONL rows and request bodies.
    public static func lineEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }

    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try AtomicFile.write(try prettyEncoder().encode(value), to: url)
    }

    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try decoder().decode(type, from: Data(contentsOf: url))
    }
}
