//
//  Layout+Adverb.swift
//  Adverb
//
//  WHAT: Spacing, radii, insets, glyph sizes and window sizes (Craft's CGFloat+Layers,
//        CraftRadius, CraftInset, CraftLayout), in one place.
//

import AppKit
import SwiftUI

extension CGFloat {
    static let hairline: CGFloat = 2
    static let layer1: CGFloat = 4
    static let snug: CGFloat = 6
    static let layer2: CGFloat = 8
    static let layer3: CGFloat = 12
    static let layer4: CGFloat = 16
    static let layer5: CGFloat = 24
    static let layer6: CGFloat = 32
    static let layer7: CGFloat = 48
}

enum AdverbRadius {
    static let chip: CGFloat = 5
    static let control: CGFloat = 7
    static let card: CGFloat = 12
    static let sheet: CGFloat = 16
    static let cell: CGFloat = 10
    /// A chip's colour swatch, a waveform's column.
    static let hairline: CGFloat = 2
}

enum AdverbInset {
    static let badge = EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
    static let chip = EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
    static let control = EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
}

enum AdverbGlyph {
    static let fine: CGFloat = 8
    static let small: CGFloat = 9
    static let caption: CGFloat = 10
    static let label: CGFloat = 11
    static let body: CGFloat = 12
    static let heading: CGFloat = 14
    static let display: CGFloat = 36
}

enum AdverbLayout {
    struct WindowSize { let ideal: CGSize; let floor: CGSize }

    static let main = WindowSize(ideal: CGSize(width: 1320, height: 860), floor: CGSize(width: 980, height: 640))
    static let settings = WindowSize(ideal: CGSize(width: 860, height: 620), floor: CGSize(width: 760, height: 520))
    static let sidebar: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (230, 260, 360)
    static let settingsSidebar: CGFloat = 210
    static let settingsMeasure: CGFloat = 600
    /// The day pane beside the calendar.
    static let dayPane: CGFloat = 420
    static let calendarCellHeight: CGFloat = 118
    static let sheetWidth: CGFloat = 560
    static let onboardingWidth: CGFloat = 560
    static let screenMargin = CGSize(width: 80, height: 60)

    static func fitted(_ ideal: CGSize) -> CGSize {
        guard let visible = NSScreen.main?.visibleFrame.size else { return ideal }
        return CGSize(width: min(ideal.width, visible.width - screenMargin.width), height: min(ideal.height, visible.height - screenMargin.height))
    }
}
