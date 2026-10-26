//
//  ImageFiles.swift
//  AdverbRender
//
//  WHAT: CGImages to JPEG and PNG files (stills, sheets, thumbnails, waveforms).
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFiles {
    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Double) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw RenderError.writer("jpeg \(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw RenderError.writer("jpeg \(url.lastPathComponent)") }
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RenderError.writer("png \(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw RenderError.writer("png \(url.lastPathComponent)") }
    }
}

extension ImageFiles {
    /// A JPEG file re-encoded with its long edge at most `maxEdge`: stills sent to Claude.
    public static func jpegData(_ url: URL, maxEdge: Int = 1024, quality: Double = 0.85) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxEdge,
                kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
