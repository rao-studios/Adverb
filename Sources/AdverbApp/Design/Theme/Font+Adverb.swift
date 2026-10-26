//
//  Font+Adverb.swift
//  Adverb
//
//  WHAT: The skill's three faces, registered from the app's resources at launch (FontRegistry), with
//        the system's faces as the fallback when a file is missing.
//

import AppKit
import CoreText
import SwiftUI

extension Font {
    static func adverbDisplay(_ size: CGFloat, italic: Bool = false) -> Font {
        FontRegistry.has("Instrument Serif") ? .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", size: size)
            : { let f = Font.system(size: size, weight: .regular, design: .serif); return italic ? f.italic() : f }()
    }

    static func adverbReading(_ size: CGFloat, italic: Bool = false) -> Font {
        FontRegistry.has("Newsreader") ? .custom(italic ? "Newsreader-Italic" : "Newsreader-Regular", size: size)
            : { let f = Font.system(size: size, design: .serif); return italic ? f.italic() : f }()
    }

    static func adverbMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        FontRegistry.has("JetBrains Mono") ? .custom(weight == .regular ? "JetBrainsMono-Regular" : "JetBrainsMono-Medium", size: size)
            : .system(size: size, weight: weight, design: .monospaced)
    }

    static func adverbGlyph(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

/// Registers the bundled faces for this process, once.
enum FontRegistry {
    nonisolated(unsafe) private static var registered: Set<String> = []

    static func registerBundled() {
        for name in ["InstrumentSerif-Regular", "InstrumentSerif-Italic", "Newsreader-Regular", "Newsreader-Italic",
                     "JetBrainsMono-Regular", "JetBrainsMono-Medium"] {
            guard let url = AdverbAssets.url(name, ext: "ttf", subdirectory: "Fonts") else { continue }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) || error != nil {
                registered.insert(name)
            }
        }
    }

    static func has(_ family: String) -> Bool {
        switch family {
        case "Instrument Serif": return registered.contains("InstrumentSerif-Regular")
        case "Newsreader": return registered.contains("Newsreader-Regular")
        case "JetBrains Mono": return registered.contains("JetBrainsMono-Regular")
        default: return false
        }
    }
}
