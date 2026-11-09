//
//  KokoroVoice.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: Kokoro voice style embedding from JSON: the mean vector, or the one
//        keyed by phoneme count (KokoroOptions.StyleVector).
//  IN:   KokoroEngine.loadVoice
//  OUT:  256-dim vector for synthesis
//

import Foundation
import Accelerate

// MARK: - Voice

/// Kokoro voice style embedding. JSON: "embedding" (the mean) plus one vector
/// per phoneme count, 1…510. PIN: embeddings used as-is (pre-conditioned, no L2).
final class KokoroVoice {
    let name: String
    private let json: Any

    private init(name: String, json: Any) {
        self.name = name
        self.json = json
    }

    /// Load a voice from `<modelsDir>/<name>.json`.
    static func load(named name: String, in modelsDir: URL) throws -> KokoroVoice {
        let url = modelsDir.appendingPathComponent("\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TTSError.invalidVoiceFile("'\(name).json' not found at \(url.path)")
        }
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        return KokoroVoice(name: name, json: json)
    }

    /// 256-dim style vector. `.mean` is the shipped lookup: flat array, then
    /// "embedding" (every bundled voice has it: the mean of keys 1…510), then
    /// voiceName, then numeric keys. `.lengthIndexed` is upstream Kokoro's:
    /// the vector for this many phonemes (BOS/EOS aside), `floor` at least.
    func embedding(for phonemeCount: Int, style: KokoroOptions.StyleVector = .mean) -> [Float]? {
        if case .lengthIndexed(let floor) = style,
           let dict = json as? [String: Any],
           let vector = lengthIndexed(dict, count: max(phonemeCount, floor)) {
            return vector
        }
        return parseVector(from: json, phonemeCount: phonemeCount)
    }

    /// The numeric key for `count`, clamped to what the file has.
    private func lengthIndexed(_ dict: [String: Any], count: Int) -> [Float]? {
        if let exact = dict[String(count)].flatMap(asFloatArray) { return exact }
        let keys = dict.keys.compactMap(Int.init).sorted()
        guard let nearest = keys.last(where: { $0 <= count }) ?? keys.first else { return nil }
        return dict[String(nearest)].flatMap(asFloatArray)
    }

    // MARK: - Private

    private func parseVector(from json: Any, phonemeCount: Int) -> [Float]? {
        if let direct = asFloatArray(json) { return direct }

        guard let dict = json as? [String: Any] else { return nil }

        if let embed = dict["embedding"], let v = asFloatArray(embed) { return v }
        if let voiceSpecific = dict[name], let v = asFloatArray(voiceSpecific) { return v }

        // Numeric keys — exact, then closest lower, then any
        var candidates: [(Int, [Float])] = []
        for (key, value) in dict {
            guard let intKey = Int(key), let v = asFloatArray(value) else { continue }
            candidates.append((intKey, v))
        }
        candidates.sort { $0.0 < $1.0 }

        if let exact = candidates.first(where: { $0.0 == phonemeCount }) { return exact.1 }
        if let lower = candidates.last(where: { $0.0 <= phonemeCount }) { return lower.1 }
        return candidates.first?.1
    }

    private func asFloatArray(_ value: Any) -> [Float]? {
        if let doubles = value as? [Double]   { return doubles.map(Float.init) }
        if let floats  = value as? [Float]    { return floats }
        if let numbers = value as? [NSNumber] { return numbers.map { $0.floatValue } }
        if let anyArr  = value as? [Any] {
            var out = [Float](); out.reserveCapacity(anyArr.count)
            for item in anyArr {
                if let n = item as? NSNumber    { out.append(n.floatValue) }
                else if let d = item as? Double { out.append(Float(d)) }
                else if let f = item as? Float  { out.append(f) }
                else { return nil }
            }
            return out
        }
        return nil
    }
}
