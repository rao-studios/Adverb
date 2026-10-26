//
//  SheetCanvas.swift
//  AdverbRender
//
//  WHAT: A CoreGraphics page with text: what contact sheets and overviews are drawn on. CoreText,
//        no AppKit, top-left origin, so it runs headless and in tests.
//

import CoreGraphics
import CoreText
import Foundation

public final class SheetCanvas {
    public let width: Int
    public let height: Int
    let ctx: CGContext

    public init?(width: Int, height: Int, background: CGColor = CGColor(srgbRed: 0.949, green: 0.945, blue: 0.933, alpha: 1)) {
        guard let ctx = ImageScaler.context(width: width, height: height) else { return nil }
        self.width = width; self.height = height; self.ctx = ctx
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
    }

    /// `rect` in top-left coordinates.
    func flip(_ rect: CGRect) -> CGRect { CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height) }

    public func draw(_ image: CGImage, in rect: CGRect) { ctx.draw(image, in: flip(rect)) }

    /// Draws `image` letterboxed into `rect`, returning where it landed.
    @discardableResult
    public func drawFitted(_ image: CGImage, in rect: CGRect) -> CGRect {
        let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        let placed = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        draw(image, in: placed)
        return placed
    }

    public func fill(_ rect: CGRect, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fill(flip(rect))
    }

    /// One line of text whose baseline-left sits at (x, y) in top-left coordinates.
    public func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: CGFloat = 0.3,
                     color: CGColor = CGColor(srgbRed: 0.114, green: 0.110, blue: 0.102, alpha: 1), shadow: Bool = false) {
        let font = CTFontCreateWithName("SF Pro Text" as CFString, size, nil)
        let traits: [CFString: Any] = [kCTFontWeightTrait: weight]
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: "SF Pro Text", kCTFontTraitsAttribute: traits] as CFDictionary)
        let weighted = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCopyFamilyName(weighted) as String == "SF Pro Text" ? weighted : font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]))
        ctx.saveGState()
        if shadow { ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: CGColor(gray: 0, alpha: 0.6)) }
        ctx.textPosition = CGPoint(x: x, y: CGFloat(height) - y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    public func image() -> CGImage? { ctx.makeImage() }
}
