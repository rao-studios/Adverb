import XCTest

/// `Sources/AdverbAgents/Granite/` is Granite for ML with nothing of Adverb in it: it imports only
/// Granite, Foundation and Combine, so it could be lifted into Granite whole.
final class GraniteFolderTests: XCTestCase {
    func testTheGraniteFolderImportsNothingOfAdverb() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AdverbAgents/Granite")
        // Every file under the folder, subfolders included: the folder can grow its own structure.
        let walker = try XCTUnwrap(FileManager.default.enumerator(atPath: folder.path))
        let files = walker.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.sorted()
        XCTAssertFalse(files.isEmpty)
        for name in files {
            let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            for line in text.split(separator: "\n") where line.hasPrefix("import ") {
                let module = String(line.dropFirst("import ".count)).trimmingCharacters(in: .whitespaces)
                XCTAssertTrue(["Granite", "Foundation", "Combine"].contains(module), "\(name) imports \(module)")
            }
        }
    }
}
