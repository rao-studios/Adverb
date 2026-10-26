//
//  Platform.swift
//  AdverbCore
//
//  WHAT: Where a post goes. Each platform has the orientation its feed favours, the wire name
//        the plan's JSON uses, and an SF Symbol for the calendar.
//

import Foundation

public enum Platform: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case instagramReels = "instagram_reels"
    case tiktok
    case youtubeShorts = "youtube_shorts"
    case x
    case linkedin
    case threads
    case bluesky

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .instagramReels: "Instagram Reels"
        case .tiktok: "TikTok"
        case .youtubeShorts: "YouTube Shorts"
        case .x: "X"
        case .linkedin: "LinkedIn"
        case .threads: "Threads"
        case .bluesky: "Bluesky"
        }
    }

    public var shortTitle: String {
        switch self {
        case .instagramReels: "Reels"
        case .tiktok: "TikTok"
        case .youtubeShorts: "Shorts"
        case .x: "X"
        case .linkedin: "LinkedIn"
        case .threads: "Threads"
        case .bluesky: "Bluesky"
        }
    }

    /// Vertical feeds take portrait; the rest take landscape.
    public var defaultOrientation: Orientation {
        switch self {
        case .instagramReels, .tiktok, .youtubeShorts: .portrait
        case .x, .linkedin, .threads, .bluesky: .landscape
        }
    }

    public var symbol: String {
        switch self {
        case .instagramReels: "camera"
        case .tiktok: "play.square.stack"
        case .youtubeShorts: "play.rectangle"
        case .x: "xmark"
        case .linkedin: "briefcase"
        case .threads: "at"
        case .bluesky: "cloud"
        }
    }
}
