//
//  NSWindow+Adverb.swift
//  Adverb
//
//  WHAT: Hosting SwiftUI in a window AppKit sizes, and opening where it was left (Craft's).
//  PIN:  AppKit owns the size: a bare NSHostingView hands SwiftUI's ideal size to the window and
//        a tall list becomes a minimum taller than the screen. The floor is contentMinSize.
//

import AppKit
import SwiftUI

extension NSWindow {
    func hostAdverb<Content: View>(_ content: Content) {
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        contentView = host
    }

    func restoreFrame(named name: String, ideal: CGSize) {
        setContentSize(AdverbLayout.fitted(ideal))
        center()
        setFrameAutosaveName(name)
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame,
              frame.height > visible.height || frame.width > visible.width else { return }
        setContentSize(AdverbLayout.fitted(ideal))
        center()
    }
}
