//
//  Mp4Atoms.swift
//  AdverbRender
//
//  WHAT: The top-level boxes of an MP4, read from their 8-byte headers. Faststart means `moov`
//        comes before `mdat`, so a player can start before the whole file arrives.
//

import Foundation

public enum Mp4Atoms {
    public struct Atom: Equatable, Sendable { public var type: String; public var offset: UInt64; public var size: UInt64 }

    public static func topLevel(_ data: Data) -> [Atom] {
        var atoms: [Atom] = []
        var offset: UInt64 = 0
        let total = UInt64(data.count)
        while offset + 8 <= total {
            let o = Int(offset)
            var size = UInt64(data[o..<o + 4].reduce(0) { ($0 << 8) | UInt32($1) })
            let type = String(decoding: data[o + 4..<o + 8], as: UTF8.self)
            if size == 1, offset + 16 <= total {
                size = data[o + 8..<o + 16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            } else if size == 0 {
                size = total - offset
            }
            guard size >= 8 else { break }
            atoms.append(Atom(type: type, offset: offset, size: size))
            offset += size
        }
        return atoms
    }

    /// Reads only the headers, hopping through the file.
    public static func topLevel(url: URL) -> [Atom] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let total = (try? handle.seekToEnd()) ?? 0
        var atoms: [Atom] = []
        var offset: UInt64 = 0
        while offset + 8 <= total {
            try? handle.seek(toOffset: offset)
            guard let header = try? handle.read(upToCount: 16), header.count >= 8 else { break }
            var size = UInt64(header[0..<4].reduce(0) { ($0 << 8) | UInt32($1) })
            let type = String(decoding: header[4..<8], as: UTF8.self)
            if size == 1, header.count == 16 { size = header[8..<16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } }
            else if size == 0 { size = total - offset }
            guard size >= 8 else { break }
            atoms.append(Atom(type: type, offset: offset, size: size))
            offset += size
        }
        return atoms
    }

    public static func isFastStart(_ atoms: [Atom]) -> Bool {
        guard let moov = atoms.firstIndex(where: { $0.type == "moov" }),
              let mdat = atoms.firstIndex(where: { $0.type == "mdat" }) else { return false }
        return moov < mdat
    }
}
