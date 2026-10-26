//
//  JSONValue.swift
//  AdverbCore
//
//  WHAT: A dependency-free JSON value: request bodies, structured-output schemas, server-tool
//        blocks echoed back on `pause_turn`.
//  PIN:  Craft's (CraftCore/Support/JSON/JSONValue.swift), without the model-text salvage that
//        needs Craft's lenient tool-call parser; Claude's structured outputs are schema-valid.
//
import Foundation

/// A dependency-free JSON value.
public enum JSONValue: Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let bool = try? container.decode(Bool.self) { self = .bool(bool); return }
        if let number = try? container.decode(Double.self) { self = .number(number); return }
        if let string = try? container.decode(String.self) { self = .string(string); return }
        if let array = try? container.decode([JSONValue].self) { self = .array(array); return }
        if let object = try? container.decode([String: JSONValue].self) { self = .object(object); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let bool): try container.encode(bool)
        case .number(let number):
            // Whole numbers serialize without a fraction: tool arguments say `3`, not `3.0`.
            if number == number.rounded(), abs(number) < 1e15 {
                try container.encode(Int64(number))
            } else {
                try container.encode(number)
            }
        case .string(let string): try container.encode(string)
        case .array(let array): try container.encode(array)
        case .object(let object): try container.encode(object)
        }
    }
}

// MARK: - Literals

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

// MARK: - Access

extension JSONValue {
    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let array) = self, array.indices.contains(index) { return array[index] }
        return nil
    }

    /// Dotted lookup: `"permissions.mode"`.
    public func value(at path: String) -> JSONValue? {
        path.split(separator: ".").reduce(Optional(self)) { current, key in current?[String(key)] }
    }

    public var isNull: Bool { if case .null = self { return true }; return false }
    public var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    public var doubleValue: Double? { if case .number(let value) = self { return value }; return nil }
    public var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let value) = self { return value }; return nil }
    public var objectValue: [String: JSONValue]? { if case .object(let value) = self { return value }; return nil }

    public var intValue: Int? {
        guard case .number(let value) = self, value == value.rounded(), abs(value) < 9.0e15 else { return nil }
        return Int(value)
    }

    /// Strings as-is, numbers and bools rendered; nil for containers and null.
    public var scalarDescription: String? {
        switch self {
        case .string(let s): return s
        case .number: return intValue.map(String.init) ?? doubleValue.map { String($0) }
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
}

// MARK: - Serialization

extension JSONValue {
    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    public func data(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Any encodable value as a JSON value — kept as JSON so the caller names no type.
    public init<T: Encodable>(encoding value: T) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    /// The payload read back as the type it was made from; nil when it is not one.
    public func decoded<T: Decodable>(as type: T.Type) -> T? {
        (try? data()).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// Compact, sorted-key JSON. Deterministic, so it doubles as a hash input.
    public var compact: String {
        (try? data()).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    public var pretty: String {
        (try? data(pretty: true)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    /// Recursive merge: `other`'s keys win; objects merge, everything else replaces.
    public func merging(_ other: JSONValue) -> JSONValue {
        guard case .object(var base) = self, case .object(let over) = other else { return other }
        for (key, value) in over {
            base[key] = base[key].map { $0.merging(value) } ?? value
        }
        return .object(base)
    }
}

// MARK: - Foundation bridging

extension JSONValue {
    /// From a `JSONSerialization` object graph.
    public init(any: Any) throws {
        switch any {
        case is NSNull: self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue) } else { self = .number(number.doubleValue) }
        case let string as String: self = .string(string)
        case let array as [Any]: self = .array(try array.map(JSONValue.init(any:)))
        case let object as [String: Any]: self = .object(try object.mapValues(JSONValue.init(any:)))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a JSON object graph: \(type(of: any))"))
        }
    }

    /// To a `JSONSerialization` object graph.
    public var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let bool): return bool
        case .number(let number):
            if number == number.rounded(), abs(number) < 9.0e15 { return Int(number) }
            return number
        case .string(let string): return string
        case .array(let array): return array.map(\.anyValue)
        case .object(let object): return object.mapValues(\.anyValue)
        }
    }
}
