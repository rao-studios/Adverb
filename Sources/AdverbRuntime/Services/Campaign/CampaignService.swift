//
//  CampaignService.swift
//  AdverbRuntime
//
//  WHAT: Every project's campaigns, as Granite state: what the sidebar lists and the calendar
//        draws, read from campaign.json and read again whenever a run changes one.
//  OUT:  CampaignService+Center, Reducers/CampaignService.Set, Ops/CampaignOps
//

import Foundation
import Granite

public struct CampaignService: GraniteService {
    @Service(.online) public var center: Center
    public init() {}
}

extension CampaignService {
    public func set(_ kind: Set.Meta.Kind) {
        let meta = Set.Meta(kind: kind)
        guard !Thread.isMainThread else { center.set.send(meta); return }
        let service = self
        DispatchQueue.main.async { service.center.set.send(meta) }
    }
}
