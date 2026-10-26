//
//  Publisher.swift
//  AdverbCore
//
//  WHAT: Where posting will plug in. Today the person posts by hand and marks the day posted
//        (ManualPublisher); an automated publisher for a platform conforms to the same protocol.
//

import Foundation

public struct PostPayload: Sendable, Equatable {
    public var video: URL
    public var caption: String
    public var hashtags: [String]
    public var altText: String
    /// SRT, for the platforms that take an uploaded caption file.
    public var captionFile: URL?
    public var scheduledAt: Date
    public var platform: Platform

    public init(video: URL, caption: String, hashtags: [String], altText: String, captionFile: URL?, scheduledAt: Date, platform: Platform) {
        self.video = video; self.caption = caption; self.hashtags = hashtags; self.altText = altText
        self.captionFile = captionFile; self.scheduledAt = scheduledAt; self.platform = platform
    }
}

public struct PublishReceipt: Sendable, Equatable {
    public var postedAt: Date
    public var url: String?

    public init(postedAt: Date, url: String?) { self.postedAt = postedAt; self.url = url }
}

public protocol Publisher: Sendable {
    var platform: Platform { get }
    func publish(_ payload: PostPayload) async throws -> PublishReceipt
}

/// The person posted it themselves; this records when.
public struct ManualPublisher: Publisher {
    public let platform: Platform
    public init(platform: Platform) { self.platform = platform }
    public func publish(_ payload: PostPayload) async throws -> PublishReceipt { PublishReceipt(postedAt: Date(), url: nil) }
}
