//
//  Color+Adverb.swift
//  Adverb
//
//  WHAT: The palette, from the rao-motion-assets skill §1: platinum paper, pearl surfaces, ink,
//        gold for the one accent. Light-locked, like the assets themselves.
//  PIN:  Numbers live here and nowhere else (DesignTokenTests).
//

import AppKit
import SwiftUI

extension Color {
    /// The page: platinum paper. #EFEEEA
    static let adverbPage = Color(red: 239 / 255, green: 238 / 255, blue: 234 / 255)
    /// Deeper platinum, for the sidebar. #E5E4DF
    static let adverbSidebar = Color(red: 229 / 255, green: 228 / 255, blue: 223 / 255)
    /// Pearl: a card, a field. #FBFAF7
    static let adverbPearl = Color(red: 251 / 255, green: 250 / 255, blue: 247 / 255)
    static let adverbPearlLow = Color(red: 241 / 255, green: 240 / 255, blue: 236 / 255)
    /// Ink. #1D1C1A
    static let adverbInk = Color(red: 29 / 255, green: 28 / 255, blue: 26 / 255)
    /// Secondary text: captions, counts, a row's second line.
    static var adverbInkDim: Color { Color.adverbInk.opacity(0.62) }
    static var adverbInkSoft: Color { Color.adverbInk.opacity(0.82) }
    static var adverbInkMuted: Color { Color.adverbInk.opacity(0.48) }
    static var adverbInkFaint: Color { Color.adverbInk.opacity(0.32) }
    /// Gold: the payoff, the selection, the one action. #B8914A
    static let adverbGold = Color(red: 184 / 255, green: 145 / 255, blue: 74 / 255)
    static let adverbGoldHi = Color(red: 226 / 255, green: 200 / 255, blue: 135 / 255)
    static let adverbGoldDeep = Color(red: 134 / 255, green: 101 / 255, blue: 43 / 255)
    /// The coin's highlight (skill .coin) and the mark's light gold.
    static let adverbCoinHi = Color(red: 243 / 255, green: 222 / 255, blue: 168 / 255)
    static let adverbGoldLight = Color(red: 217 / 255, green: 182 / 255, blue: 110 / 255)
    /// Text on gold foil.
    static let adverbOnGold = Color(red: 42 / 255, green: 32 / 255, blue: 16 / 255)
    /// The brushstroke: a source, an author. rgba(206,160,72,.45)
    static var adverbBrush: Color { Color(red: 206 / 255, green: 160 / 255, blue: 72 / 255).opacity(0.45) }
    static let adverbNight = Color(red: 14 / 255, green: 16 / 255, blue: 21 / 255)
    static let adverbVeil = Color(red: 43 / 255, green: 76 / 255, blue: 83 / 255)
    static var adverbBorder: Color { Color.adverbInk.opacity(0.11) }
    static let adverbError = Color(red: 176 / 255, green: 72 / 255, blue: 60 / 255)
    static let adverbSuccess = Color(red: 78 / 255, green: 128 / 255, blue: 88 / 255)
    static let adverbWarning = Color(red: 186 / 255, green: 120 / 255, blue: 44 / 255)
}

extension Color {
    static var adverbFillTrace: Color { Color.adverbInk.opacity(0.03) }
    static var adverbFill: Color { Color.adverbInk.opacity(0.06) }
    static var adverbFillHover: Color { Color.adverbInk.opacity(0.10) }
    static var adverbFillSelected: Color { Color.adverbGold.opacity(0.16) }
    static var adverbShadow: Color { Color(red: 50 / 255, green: 48 / 255, blue: 42 / 255).opacity(0.18) }

    /// The page's gradient (skill §1: 175°, #EFEEEA → #E2E1DC → #D3D2CC).
    static let adverbPaper = LinearGradient(colors: [Color(red: 239 / 255, green: 238 / 255, blue: 234 / 255),
                                                     Color(red: 226 / 255, green: 225 / 255, blue: 220 / 255),
                                                     Color(red: 211 / 255, green: 210 / 255, blue: 204 / 255)],
                                            startPoint: UnitPoint(x: 0.46, y: 0), endPoint: UnitPoint(x: 0.54, y: 1))
    /// Gold foil, for the one premium mark (skill §1).
    static let adverbFoil = LinearGradient(colors: [Color(red: 238 / 255, green: 217 / 255, blue: 163 / 255),
                                                    Color(red: 207 / 255, green: 168 / 255, blue: 93 / 255),
                                                    Color(red: 168 / 255, green: 127 / 255, blue: 59 / 255),
                                                    Color(red: 217 / 255, green: 187 / 255, blue: 121 / 255)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    /// A project's label dot.
    static func adverbLabel(_ label: String) -> Color {
        switch label {
        case "gold": return .adverbGold
        case "night": return .adverbNight
        case "teal": return .adverbVeil
        case "platinum": return Color(red: 196 / 255, green: 195 / 255, blue: 189 / 255)
        default: return .adverbInk
        }
    }
}

extension NSColor {
    /// The page, for AppKit windows. PIN: keep in step with `Color.adverbPage`.
    static let adverbPage = NSColor(srgbRed: 239 / 255, green: 238 / 255, blue: 234 / 255, alpha: 1)
    static let adverbGold = NSColor(srgbRed: 184 / 255, green: 145 / 255, blue: 74 / 255, alpha: 1)
}
