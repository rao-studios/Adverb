//
//  AdverbType.swift
//  Adverb
//
//  WHAT: Text roles, one per job (Craft's CraftType), in the skill's faces: Instrument Serif for
//        titles (an italic gold payoff where a title has one), Newsreader for what is read,
//        JetBrains Mono uppercase for labels and code, the system sans for chrome.
//  PIN:  A view picks a role, never a size.
//

import SwiftUI

enum AdverbType {
    /// A window's or an empty state's big title.
    case display
    /// A page's title: a project, a campaign, a day.
    case pageTitle
    /// A card's or a sheet's title.
    case title
    /// A number read at a glance.
    case figure
    /// Reading text: captions of posts, notes, reasons.
    case reading
    case readingSmall
    /// Chrome.
    case heading
    case body
    case label
    case labelStrong
    case caption
    case captionStrong
    case fine
    /// SMALL CAPS MONO KICKERS AND SECTION HEADERS.
    case section
    case badge
    /// Paths, ids, times, code.
    case identifier
    case code
    case codeSmall

    enum Face { case display, reading, sans, mono }

    var spec: (face: Face, size: CGFloat, weight: Font.Weight, italic: Bool) {
        switch self {
        case .display: return (.display, 40, .regular, false)
        case .pageTitle: return (.display, 30, .regular, false)
        case .title: return (.display, 22, .regular, false)
        case .figure: return (.display, 24, .regular, false)
        case .reading: return (.reading, 15, .regular, false)
        case .readingSmall: return (.reading, 13, .regular, false)
        case .heading: return (.sans, 13, .semibold, false)
        case .body: return (.sans, 13, .regular, false)
        case .label: return (.sans, 12, .regular, false)
        case .labelStrong: return (.sans, 12, .medium, false)
        case .caption: return (.sans, 11, .regular, false)
        case .captionStrong: return (.sans, 11, .medium, false)
        case .fine: return (.sans, 10, .regular, false)
        case .section: return (.mono, 10, .medium, false)
        case .badge: return (.mono, 9, .medium, false)
        case .identifier: return (.mono, 11, .regular, false)
        case .code: return (.mono, 12, .regular, false)
        case .codeSmall: return (.mono, 10, .regular, false)
        }
    }

    var font: Font {
        let s = spec
        switch s.face {
        case .display: return .adverbDisplay(s.size, italic: s.italic)
        case .reading: return .adverbReading(s.size, italic: s.italic)
        case .sans: return .system(size: s.size, weight: s.weight)
        case .mono: return .adverbMono(s.size, weight: s.weight)
        }
    }

    var kerning: CGFloat {
        switch self {
        case .section, .badge: return 1.4
        case .display, .pageTitle: return -0.3
        default: return 0
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .reading: return 4
        case .readingSmall: return 3
        default: return 0
        }
    }
}
