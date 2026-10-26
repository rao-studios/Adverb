//
//  main.swift
//  Adverb
//
//  WHAT: A windowed app: Dock tile, main menu. AppKit owns the process, SwiftUI every surface
//        (Craft's main.swift).
//

import AppKit

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AdverbAppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
withExtendedLifetime(delegate) { app.run() }
