//
//  ContactSheet.swift
//  AdverbRender
//
//  WHAT: rao-motion-assets §8, natively: one sheet per topic with both versions — frames at
//        18 / 42 / 66 / 97 % of each MP4, the portrait frames in a row at 270×480 on the left and
//        the landscape frames in a 2×2 grid at 480×270 on the right, a header ("name · length ·
//        portrait + landscape") and a time label on each frame. And the series overview: one
//        mid frame per file in a 4-column grid, letterboxed into equal cells, names under each.
//        A day's first sheet is drawn from its stills (`make(stills:)`), before any video: the page
//        is judged there, then rendered, and the video's sheet replaces it.
//  PIN:  The layout is measured from the sheets the skill shipped (2152×638 on #F2F1EE).
//

import AdverbCore
import CoreGraphics
import Foundation

public enum ContactSheet {
    public static let fractions: [Double] = [0.18, 0.42, 0.66, 0.97]

    public static func make(portrait: URL, landscape: URL, title: String, duration: Int, to out: URL) async throws {
        let p = FrameGrabber(url: portrait), l = FrameGrabber(url: landscape)
        var pFrames: [(CGImage, Double)] = [], lFrames: [(CGImage, Double)] = []
        for f in fractions {
            pFrames.append(try await p.image(atFraction: f, maxSize: CGSize(width: 540, height: 960)))
            lFrames.append(try await l.image(atFraction: f, maxSize: CGSize(width: 960, height: 540)))
        }
        try draw(portrait: pFrames, landscape: lFrames, title: title, duration: duration, to: out)
    }

    /// The same sheet from the stills a page was checked with (before any video exists): what a
    /// day is judged by before it renders. The stills are at the same fractions.
    public static func make(stills: [Still], paths: CampaignPaths, title: String, duration: Int, to out: URL) throws {
        func frames(_ o: Orientation) -> [(CGImage, Double)] {
            stills.filter { $0.orientation == o }.sorted { $0.time < $1.time }.compactMap { still in
                ImageFiles.read(paths.url(still.path)).map { ($0, still.time) }
            }
        }
        let p = frames(.portrait), l = frames(.landscape)
        guard !p.isEmpty, !l.isEmpty else { throw RenderError.writer("sheet: no stills to lay out") }
        try draw(portrait: p, landscape: l, title: title, duration: duration, to: out)
    }

    static func draw(portrait: [(CGImage, Double)], landscape: [(CGImage, Double)], title: String, duration: Int, to out: URL) throws {
        let margin: CGFloat = 16, top: CGFloat = 66, gap: CGFloat = 16
        let pw: CGFloat = 270, ph: CGFloat = 480, lw: CGFloat = 480, lh: CGFloat = 270
        let width = Int(margin + 4 * pw + 3 * gap + gap + 2 * lw + gap + margin)   // 2152
        let height = Int(top + ph + 92)                                            // 638
        guard let canvas = SheetCanvas(width: width, height: height) else { throw RenderError.writer("sheet canvas") }
        canvas.text("\(title)  ·  \(duration)s  ·  portrait + landscape", x: margin, y: 36, size: 22, weight: 0)
        for (i, (image, t)) in portrait.prefix(4).enumerated() {
            let rect = CGRect(x: margin + CGFloat(i) * (pw + gap), y: top, width: pw, height: ph)
            canvas.draw(image, in: rect)
            canvas.text(String(format: "%.1fs", t), x: rect.minX + 8, y: rect.maxY - 12, size: 20, weight: 0.2,
                        color: CGColor(gray: 1, alpha: 1), shadow: true)
        }
        let lx = margin + 4 * pw + 3 * gap + gap
        for (i, (image, t)) in landscape.prefix(4).enumerated() {
            let col = CGFloat(i % 2), row = CGFloat(i / 2)
            let rect = CGRect(x: lx + col * (lw + gap), y: top + row * (lh + gap), width: lw, height: lh)
            canvas.draw(image, in: rect)
            canvas.text(String(format: "%.1fs", t), x: rect.minX + 8, y: rect.maxY - 12, size: 20, weight: 0.2,
                        color: CGColor(gray: 1, alpha: 1), shadow: true)
        }
        guard let image = canvas.image() else { throw RenderError.writer("sheet image") }
        try ImageFiles.writeJPEG(image, to: out, quality: 0.9)
    }

    /// One mid frame per file, four to a row, letterboxed into equal cells, named under each. A file
    /// is a video (its middle frame) or an image (a still, for a day not rendered yet).
    public static func overview(files: [(name: String, url: URL)], to out: URL, columns: Int = 4) async throws {
        guard !files.isEmpty else { return }
        let cell: CGFloat = 380, label: CGFloat = 44, gap: CGFloat = 16, margin: CGFloat = 16
        let rows = (files.count + columns - 1) / columns
        let width = Int(margin * 2 + CGFloat(columns) * cell + CGFloat(columns - 1) * gap)
        let height = Int(margin * 2 + CGFloat(rows) * (cell + label) + CGFloat(max(0, rows - 1)) * gap)
        guard let canvas = SheetCanvas(width: width, height: height) else { throw RenderError.writer("overview canvas") }
        for (i, file) in files.enumerated() {
            let col = CGFloat(i % columns), row = CGFloat(i / columns)
            let box = CGRect(x: margin + col * (cell + gap), y: margin + row * (cell + label + gap), width: cell, height: cell)
            canvas.fill(box, CGColor(srgbRed: 0.886, green: 0.882, blue: 0.863, alpha: 1))
            if ["jpg", "jpeg", "png"].contains(file.url.pathExtension.lowercased()) {
                if let image = ImageFiles.read(file.url) { canvas.drawFitted(image, in: box) }
            } else if let (image, _) = try? await FrameGrabber(url: file.url).image(atFraction: 0.5, maxSize: CGSize(width: cell * 2, height: cell * 2)) {
                canvas.drawFitted(image, in: box)
            }
            canvas.text(file.name, x: box.minX, y: box.maxY + 30, size: 20, weight: 0)
        }
        guard let image = canvas.image() else { throw RenderError.writer("overview image") }
        try ImageFiles.writeJPEG(image, to: out, quality: 0.88)
    }
}
