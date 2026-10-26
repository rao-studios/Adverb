//
//  AppIdentity.swift
//  AdverbCore
//
//  WHAT: Who an asset is for: the kicker it opens with, the end card it closes on, and the
//        sites Claude may read before it writes (rao-motion-assets §2 end-card defaults, §3 rule 1).
//

import Foundation

public struct AppIdentity: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var siteURL: String?
    public var repoURL: String?
    public var kicker: String
    public var endTitle: String
    public var endSub: String
    public var endSub2: String
    /// Craft and Veil are "Coming soon" until their sites say otherwise (§3 rule 4).
    public var comingSoon: Bool

    public init(name: String, siteURL: String? = nil, repoURL: String? = nil, kicker: String, endTitle: String,
                endSub: String, endSub2: String, comingSoon: Bool = false) {
        self.name = name; self.siteURL = siteURL; self.repoURL = repoURL; self.kicker = kicker
        self.endTitle = endTitle; self.endSub = endSub; self.endSub2 = endSub2; self.comingSoon = comingSoon
    }

    /// The URLs the planner may fetch: listed in the prompt, since web fetch only reads URLs it
    /// was shown.
    public var sources: [String] { [siteURL, repoURL].compactMap { $0 }.filter { !$0.isEmpty } }

    public static let ambient = AppIdentity(name: "Ambient", siteURL: "https://ambient.rao.nyc", kicker: "Ambient, explained",
                                            endTitle: "Ambient", endSub: "ambient.rao.nyc", endSub2: "Personal · private · cited · on your Mac")
    public static let aii = AppIdentity(name: "AII", repoURL: "https://github.com/rao-studios/AII", kicker: "Under Ambient: AII",
                                        endTitle: "AII", endSub: "github.com/rao-studios/AII", endSub2: "Open source · on-device · powers Ambient")
    public static let craft = AppIdentity(name: "Craft", siteURL: "https://craft.rao.nyc", kicker: "Craft, coming soon",
                                          endTitle: "Craft", endSub: "craft.rao.nyc", endSub2: "Coming soon", comingSoon: true)
    public static let veil = AppIdentity(name: "Veil", siteURL: "https://veil.rao.nyc", kicker: "Veil, coming soon",
                                         endTitle: "Veil", endSub: "veil.rao.nyc", endSub2: "Coming soon", comingSoon: true)
    public static let rao = AppIdentity(name: "Rao", siteURL: "https://rao.nyc", kicker: "Rao Studios",
                                        endTitle: "Rao", endSub: "rao.nyc", endSub2: "Personal · private · cited · credited")

    public static let presets: [AppIdentity] = [.ambient, .aii, .craft, .veil, .rao]

    /// A new app's identity, before the person edits it.
    public static func custom(_ name: String) -> AppIdentity {
        AppIdentity(name: name, kicker: "\(name), explained", endTitle: name, endSub: "", endSub2: "Personal · private · cited · credited")
    }
}
