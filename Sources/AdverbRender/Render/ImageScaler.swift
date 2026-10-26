//
//  ImageScaler.swift
//  AdverbRender
//
//  WHAT: High-quality scaling for frames: a supersampled 2× frame down to the asset's size, a
//        frame down to a contact-sheet cell.
//

import CoreGraphics
import Foundation

public enum ImageScaler {
    public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    public static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    public static func scale(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let ctx = context(width: width, height: height) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
