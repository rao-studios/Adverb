//
//  AdverbAssets.swift
//  Adverb
//
//  WHAT: The app's own resources (the UI faces, the mark) from its resource bundle.
//  PIN:  Never `Bundle.module`: its accessor traps when the bundle is not beside the binary, which is
//        the case inside Adverb.app (make-app.sh puts it in Contents/Resources). Look there first,
//        then beside the binary (the dev build). Ambient's AppAssets, Craft's CraftAssets.
//

import AppKit

enum AdverbAssets {
    static let bundleName = "Adverb_AdverbApp.bundle"

    static func url(_ name: String, ext: String, subdirectory: String? = nil) -> URL? {
        let candidates: [URL?] = [Bundle.main.resourceURL?.appendingPathComponent(bundleName),
                                  Bundle.main.bundleURL.appendingPathComponent(bundleName),
                                  Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(bundleName)]
        for case let bundleURL? in candidates {
            guard let bundle = Bundle(url: bundleURL) else { continue }
            let sub = ["Resources" + (subdirectory.map { "/\($0)" } ?? ""), subdirectory].compactMap { $0 }
            for s in sub {
                if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: s) { return url }
            }
            if let url = bundle.url(forResource: name, withExtension: ext) { return url }
        }
        return nil
    }
}
