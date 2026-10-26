//
//  KitBundle.swift
//  AdverbCore
//
//  WHAT: AdverbCore's resources (the motion kit, the prompts) from its resource bundle.
//  PIN:  Never `Bundle.module`. Its generated accessor traps when the bundle is not beside the
//        executable, which is exactly the case inside Adverb.app, where make-app.sh puts it in
//        Contents/Resources (Ambient's AppAssets, Craft's CraftAssets). Look there first, then
//        beside the binary (the dev build and the tests).
//

import Foundation

public enum KitBundle {
    public static let bundleName = "Adverb_AdverbCore.bundle"

    /// The bundle's `Resources` folder: `Kit/`, `Prompts/`.
    public static var resources: URL? {
        for root in candidateRoots() {
            let bundle = root.appendingPathComponent(bundleName)
            for inner in ["Contents/Resources/Resources", "Resources"] {
                let url = bundle.appendingPathComponent(inner, isDirectory: true)
                if AtomicFile.isDirectory(url) { return url }
            }
        }
        return nil
    }

    public static var kit: URL? { resources?.appendingPathComponent("Kit", isDirectory: true) }
    public static var prompts: URL? { resources?.appendingPathComponent("Prompts", isDirectory: true) }

    public static func url(_ relative: String) -> URL? {
        guard let resources, case let url = resources.appendingPathComponent(relative),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    public static func text(_ relative: String) -> String? {
        url(relative).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    private static func candidateRoots() -> [URL] {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() { roots.append(executable) }
        // Test bundles: the .xctest sits beside the resource bundles in .build/<config>.
        for bundle in Bundle.allBundles where bundle.bundleURL.pathExtension == "xctest" {
            roots.append(bundle.bundleURL.deletingLastPathComponent())
        }
        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
