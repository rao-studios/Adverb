import Foundation
import Testing

/// Numbers live in Design/Theme (Craft's DesignTokenTests): a view picks a token, never a size, a
/// radius, a spacing or a colour of its own.
@Suite struct DesignTokenTests {
    static let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/AdverbApp")

    static let banned: [(pattern: String, why: String)] = [
        (#"Color\(red:"#, "a colour outside the palette"),
        (#"\.system\(size:"#, "a font size outside AdverbType"),
        (#"cornerRadius: \d"#, "a radius outside AdverbRadius"),
        (#"spacing: [1-9]"#, "a spacing outside the layers"),
        (#"\.padding\([^)]*\b[1-9]\d*\)"#, "a padding outside the layers"),
    ]

    @Test func viewsUseTokens() throws {
        let files = FileManager.default.enumerator(atPath: Self.app.path)!.compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") && !$0.hasPrefix("Design/Theme/") }
        #expect(!files.isEmpty)
        var found: [String] = []
        for file in files {
            let text = try String(contentsOf: Self.app.appendingPathComponent(file), encoding: .utf8)
            for (n, line) in text.components(separatedBy: "\n").enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for rule in Self.banned where line.range(of: rule.pattern, options: .regularExpression) != nil {
                    found.append("\(file):\(n + 1) \(rule.why): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }
}
