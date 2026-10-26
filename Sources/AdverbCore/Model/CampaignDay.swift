//
//  CampaignDay.swift
//  AdverbCore
//
//  WHAT: One posting day: when (an absolute instant, and the local time with the reason for it),
//        where, the topic of its asset, the social caption and hashtags, and the asset once built.
//  PIN:  `index` is the NN in file names (01-topic). It orders files and never appears on screen
//        (rao-motion-assets: never number assets).
//

import Foundation

public enum PostStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case planned, rendered, posted, skipped
    public var title: String { rawValue.capitalized }
}

public struct PostTarget: Codable, Sendable, Equatable, Hashable {
    public var platform: Platform
    public var orientation: Orientation
    public var postedAt: Date?
    public var postURL: String?

    public init(platform: Platform, orientation: Orientation? = nil, postedAt: Date? = nil, postURL: String? = nil) {
        self.platform = platform; self.orientation = orientation ?? platform.defaultOrientation
        self.postedAt = postedAt; self.postURL = postURL
    }
}

public struct CampaignDay: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var index: Int
    /// "yyyy-MM-dd" in the brief's zone.
    public var date: String
    public var postAt: Date
    /// "09:30", in the brief's zone.
    public var postTimeLocal: String
    public var timeReason: String
    /// The primary platform first.
    public var targets: [PostTarget]
    public var topic: TopicBrief
    public var caption: String
    public var hashtags: [String]
    public var hook: String
    public var cta: String
    public var status: PostStatus
    public var asset: Asset?
    /// Why the last build of this day stopped, when it did.
    public var problem: String?

    public init(id: UUID = UUID(), index: Int, date: String, postAt: Date, postTimeLocal: String, timeReason: String,
                targets: [PostTarget], topic: TopicBrief, caption: String, hashtags: [String], hook: String, cta: String,
                status: PostStatus = .planned, asset: Asset? = nil, problem: String? = nil) {
        self.id = id; self.index = index; self.date = date; self.postAt = postAt; self.postTimeLocal = postTimeLocal
        self.timeReason = timeReason; self.targets = targets; self.topic = topic; self.caption = caption
        self.hashtags = hashtags; self.hook = hook; self.cta = cta; self.status = status; self.asset = asset; self.problem = problem
    }

    public var primary: Platform { targets.first?.platform ?? .instagramReels }

    /// "03-highlight": the asset's folder and file stem.
    public var stem: String { String(format: "%02d-%@", index, topic.slug) }

    /// Caption plus hashtags, ready to paste.
    public var postText: String {
        let tags = hashtags.map { $0.hasPrefix("#") ? $0 : "#\($0)" }.joined(separator: " ")
        return tags.isEmpty ? caption : "\(caption)\n\n\(tags)"
    }
}
