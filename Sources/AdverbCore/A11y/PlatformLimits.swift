//
//  PlatformLimits.swift
//  AdverbCore
//
//  WHAT: How much text each platform takes: the post caption, alt text, hashtags, and whether a
//        caption file can be uploaded with the video.
//  PIN:  Reported figures (Buffer, Publer, Upload-Post help pages, checked 2026-10-26); the
//        platforms publish few of these themselves. Instagram's 2,200 is widely reported, not
//        Meta's. Reels, TikTok and Shorts take no alt text on a video: nil there.
//

import Foundation

public enum PlatformLimits {
    public static func captionMax(_ p: Platform) -> Int {
        switch p {
        case .instagramReels, .tiktok: 2_200
        case .youtubeShorts: 5_000
        case .x: 280
        case .linkedin: 3_000
        case .threads: 500
        case .bluesky: 300
        }
    }

    public static func altTextMax(_ p: Platform) -> Int? {
        switch p {
        case .x: 1_000
        case .linkedin: 4_086
        case .bluesky: 2_000
        case .threads: 1_000
        case .instagramReels, .tiktok, .youtubeShorts: nil
        }
    }

    public static func hashtagMax(_ p: Platform) -> Int? {
        switch p {
        case .instagramReels: 30
        default: nil
        }
    }

    /// Platforms that take an uploaded caption file (SRT or VTT) with a video.
    public static func acceptsCaptionFile(_ p: Platform) -> Bool {
        switch p {
        case .youtubeShorts, .linkedin, .x, .bluesky: true
        case .instagramReels, .tiktok, .threads: false
        }
    }

    /// Characters a post uses (caption + hashtags), counted as the platforms count: by grapheme.
    public static func length(caption: String, hashtags: [String]) -> Int {
        let tags = hashtags.map { $0.hasPrefix("#") ? $0 : "#\($0)" }.joined(separator: " ")
        return tags.isEmpty ? caption.count : caption.count + 2 + tags.count
    }
}
