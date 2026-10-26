//
//  BeatTimeline.swift
//  Adverb
//
//  WHAT: The whole song: its loudness as platinum columns, a tick on every beat (taller and gold on
//        a downbeat), and the asset's window as a pearl band to drag along it. A drag snaps the
//        window's start to the nearest downbeat; hold ⌥ to place it freely.
//

import AdverbCore
import AdverbRender
import SwiftUI

struct BeatTimeline: View {
    let grid: BeatGrid
    let duration: Double
    @Binding var inPoint: Double
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width, height = proxy.size.height
            let scale = width / max(grid.duration, 1)
            let columns = Waveform.columns(grid, columns: max(1, Int(width / 3)))
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let colW = size.width / CGFloat(max(columns.count, 1))
                    for (i, v) in columns.enumerated() {
                        let h = max(2, CGFloat(v) * (size.height - 24))
                        ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * colW, y: (size.height - h) / 2, width: max(1, colW - 1), height: h), cornerRadius: AdverbRadius.hairline / 2),
                                 with: .color(Color.adverbInkFaint))
                    }
                    let downs = Set(grid.downbeats.map { Int(($0 * 1000).rounded()) })
                    for b in grid.beats {
                        let x = CGFloat(b) * size.width / CGFloat(max(grid.duration, 1))
                        let down = downs.contains(Int((b * 1000).rounded()))
                        let h: CGFloat = down ? size.height : size.height * 0.28
                        ctx.fill(Path(CGRect(x: x, y: (size.height - h) / 2, width: down ? 1.5 : 1, height: h)),
                                 with: .color(down ? Color.adverbGold : Color.adverbInkFaint))
                    }
                }
                RoundedRectangle(cornerRadius: AdverbRadius.chip)
                    .fill(Color.adverbBrush)
                    .overlay(RoundedRectangle(cornerRadius: AdverbRadius.chip).strokeBorder(Color.adverbGold, lineWidth: 1.5))
                    .frame(width: max(8, CGFloat(duration) * scale), height: height)
                    .offset(x: CGFloat(inPoint) * scale)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        let start = dragStart ?? inPoint
                        if dragStart == nil { dragStart = inPoint }
                        var t = start + Double(value.translation.width / scale)
                        t = min(max(0, t), max(0, grid.duration - duration))
                        if !NSEvent.modifierFlags.contains(.option), let snap = grid.downbeats.min(by: { abs($0 - t) < abs($1 - t) }), abs(snap - t) < 1.5 {
                            t = min(snap, max(0, grid.duration - duration))
                        }
                        inPoint = t
                    }.onEnded { _ in dragStart = nil })
                    .help("Drag to choose where in the song the asset starts. ⌥ places it freely.")
            }
            .background(Color.adverbPearl, in: RoundedRectangle(cornerRadius: AdverbRadius.control))
            .overlay(RoundedRectangle(cornerRadius: AdverbRadius.control).strokeBorder(Color.adverbBorder))
        }
    }
}

/// The asset's own seconds, with the beats that fall in them: what the scenes will meet.
struct BeatWindow: View {
    let grid: BeatGrid
    let duration: Double

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / CGFloat(max(duration, 1))
            for t in stride(from: 0.0, through: duration, by: 1) {
                ctx.fill(Path(CGRect(x: CGFloat(t) * s, y: size.height - 6, width: 1, height: 6)), with: .color(Color.adverbInkFaint))
            }
            let downs = Set(grid.downbeats.map { Int(($0 * 1000).rounded()) })
            for b in grid.beats {
                let down = downs.contains(Int((b * 1000).rounded()))
                let r: CGFloat = down ? 5 : 3
                ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(b) * s - r, y: size.height / 2 - r - 4, width: r * 2, height: r * 2)),
                         with: .color(down ? Color.adverbGold : Color.adverbInkMuted))
            }
            let end = duration - 1.6
            ctx.fill(Path(CGRect(x: CGFloat(end) * s, y: 0, width: 1, height: size.height - 8)), with: .color(Color.adverbInk.opacity(0.4)))
        }
        .overlay(alignment: .bottomTrailing) {
            Text("end card").adverbType(.fine).foregroundStyle(Color.adverbInkMuted).padding(.trailing, .layer1)
        }
    }
}
