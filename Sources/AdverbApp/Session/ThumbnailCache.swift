//
//  ThumbnailCache.swift
//  Adverb
//
//  WHAT: Day-cell thumbnails from the asset's stills, decoded once at cell size and kept in memory.
//

import AppKit
import ImageIO

@MainActor
enum ThumbnailCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(_ url: URL, maxPixels: Int = 360) -> NSImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(modified)|\(maxPixels)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                       kCGImageSourceThumbnailMaxPixelSize: maxPixels] as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }
}
