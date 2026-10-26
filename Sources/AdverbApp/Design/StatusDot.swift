//
//  StatusDot.swift
//  Adverb
//
//  WHAT: An 8-pt status dot. Hollow: nothing there yet. Pulsing: working on it.
//

import SwiftUI

struct StatusDot: View {
    let color: Color
    var hollow = false
    var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    private var animates: Bool { pulsing && !reduceMotion }

    var body: some View {
        Group {
            if hollow { Circle().strokeBorder(color, lineWidth: 1) } else { Circle().fill(color) }
        }
        .frame(width: 8, height: 8)
        .opacity(animates && dim ? 0.3 : 1)
        .animation(animates ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default, value: dim)
        .onAppear { dim = animates }
        .onChange(of: animates) { _, on in dim = on }
    }
}
